import 'package:workmanager/workmanager.dart';
import '../helpers/database_helper.dart';
import '../models/transfer_task.dart';
import 'transfer_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    final dbHelper = DatabaseHelper();
    final transferService = TransferService();

    if (taskName == 'resumeTransfers') {
      List<TransferTask> interruptedTasks = await dbHelper.getTasksByState(TransferState.transferring);

      for (var task in interruptedTasks) {
        await dbHelper.updateProgress(task.id, task.bytesTransferred, TransferState.retrying);
        
        int retryCount = 0;
        bool success = false;
        
        while (retryCount < 3 && !success) {
          try {
            if (task.isDownload) {
              await transferService.startDownload(task);
            } else {
              await transferService.startUpload(task);
            }
            
            TransferTask? updatedTask = await dbHelper.getTask(task.id);
            if (updatedTask != null && (updatedTask.state == TransferState.completed || updatedTask.state == TransferState.paused)) {
              success = true;
            } else {
              retryCount++;
              await Future.delayed(const Duration(seconds: 2));
            }
          } catch (e) {
            retryCount++;
            await Future.delayed(const Duration(seconds: 2));
          }
        }
        
        if (!success) {
          await dbHelper.updateProgress(task.id, task.bytesTransferred, TransferState.failed);
        }
      }
    }
    
    return Future.value(true);
  });
}

class BackgroundService {
  static void initialize() {
    Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: true,
    );
  }

  static void registerTransferTask() {
    Workmanager().registerOneOffTask(
      "transferTask_1",
      "resumeTransfers",
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      initialDelay: const Duration(seconds: 5),
    );
  }
}
