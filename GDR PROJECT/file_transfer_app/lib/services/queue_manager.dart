import 'dart:async';
import '../helpers/database_helper.dart';
import '../models/transfer_task.dart';
import 'transfer_service.dart';

class QueueManager {
  static final QueueManager _instance = QueueManager._internal();
  factory QueueManager() => _instance;

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final TransferService _transferService = TransferService();
  
  final int _maxConcurrent = 2;
  int _activeCount = 0;
  bool _isProcessing = false;

  QueueManager._internal();

  /// Processes the queue to ensure up to _maxConcurrent tasks are running.
  Future<void> processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      List<TransferTask> activeTasks = await _dbHelper.getTasksByState(TransferState.transferring);
      List<TransferTask> retryingTasks = await _dbHelper.getTasksByState(TransferState.retrying);
      _activeCount = activeTasks.length + retryingTasks.length;

      while (_activeCount < _maxConcurrent) {
        List<TransferTask> queuedTasks = await _dbHelper.getTasksByState(TransferState.queued);
        if (queuedTasks.isEmpty) break;

        TransferTask nextTask = queuedTasks.first;
        
        // Optimistically mark as transferring to avoid duplicate picking
        await _dbHelper.updateProgress(nextTask.id, nextTask.bytesTransferred, TransferState.transferring);
        _activeCount++;
        
        _startTask(nextTask);
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _startTask(TransferTask task) async {
    try {
      if (task.isDownload) {
        await _transferService.startDownload(task);
      } else {
        await _transferService.startUpload(task);
      }
    } finally {
      // This block executes when the task reaches completed, failed, or paused state.
      // We automatically attempt to pick up the next queued task.
      processQueue();
    }
  }

  /// Add a new task and trigger queue processing
  Future<void> enqueue(TransferTask task) async {
    task.state = TransferState.queued;
    await _dbHelper.saveTask(task);
    processQueue();
  }

  /// Pause a task and immediately process queue for next available task
  void pauseTask(String fileId) {
    _transferService.pause(fileId);
    // processQueue() will be called automatically via the _startTask's finally block
    // once the transfer service physically stops the network call.
  }
}
