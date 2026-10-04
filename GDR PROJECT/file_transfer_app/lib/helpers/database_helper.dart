import 'dart:async';
import '../models/transfer_task.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  final Map<String, TransferTask> _tasks = {};
  
  final StreamController<List<TransferTask>> _tasksController = StreamController<List<TransferTask>>.broadcast();

  Stream<List<TransferTask>> get tasksStream => _tasksController.stream;

  void _notifyListeners() {
    _tasksController.add(_tasks.values.toList());
  }

  List<TransferTask> getAllTasksSync() {
    return _tasks.values.toList();
  }

  Future<void> saveTask(TransferTask task) async {
    _tasks[task.id] = task;
    _notifyListeners();
  }

  Future<TransferTask?> getTask(String id) async {
    return _tasks[id];
  }

  Future<List<TransferTask>> getTasksByState(TransferState state) async {
    return _tasks.values.where((task) => task.state == state).toList();
  }

  Future<void> updateProgress(String id, int bytesTransferred, TransferState state, {double speed = 0.0}) async {
    if (_tasks.containsKey(id)) {
      _tasks[id]!.bytesTransferred = bytesTransferred;
      _tasks[id]!.state = state;
      if (speed > 0) _tasks[id]!.speed = speed;
      _notifyListeners();
    }
  }

  Future<void> deleteTask(String id) async {
    _tasks.remove(id);
    _notifyListeners();
  }
}
