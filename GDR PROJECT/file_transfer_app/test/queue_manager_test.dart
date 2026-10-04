import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../lib/models/transfer_task.dart';
import '../lib/helpers/database_helper.dart';
import '../lib/services/queue_manager.dart';

void main() {
  test('QueueManager limits concurrent transfers and auto-advances', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final int port = server.port;
    final int totalSize = 20 * 1024 * 1024; // 20MB files
    
    server.listen((HttpRequest request) async {
      if (request.uri.path == '/download') {
        String? rangeHeader = request.headers.value('range');
        int start = 0;
        int end = totalSize - 1;

        if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
          final parts = rangeHeader.substring(6).split('-');
          if (parts.isNotEmpty && parts[0].isNotEmpty) start = int.parse(parts[0]);
          if (parts.length > 1 && parts[1].isNotEmpty) end = int.parse(parts[1]);
        }

        int chunkLength = end - start + 1;
        request.response.statusCode = 206;
        request.response.headers.add('content-length', chunkLength.toString());
        request.response.headers.add('content-range', 'bytes $start-$end/$totalSize');
        
        // Artificially delay the response so tasks stay in transferring state
        await Future.delayed(const Duration(milliseconds: 300));
        
        request.response.add(List<int>.generate(chunkLength, (i) => i % 256));
        await request.response.close();
      } else {
        request.response.statusCode = 404;
        await request.response.close();
      }
    });

    final queueManager = QueueManager();
    final dbHelper = DatabaseHelper();

    // 1. Queue 5 files
    for (int i = 1; i <= 5; i++) {
      String path = 'test_file_$i.bin';
      if (File(path).existsSync()) File(path).deleteSync();
      
      var task = TransferTask(
        id: 'task_$i',
        url: 'http://localhost:$port/download',
        filePath: path,
        isDownload: true,
        totalBytes: totalSize,
      );
      await queueManager.enqueue(task);
    }

    // Wait for the queue to start processing
    await Future.delayed(const Duration(milliseconds: 100));

    // 2. Verify exactly 2 are transferring, 3 are queued
    var activeTasks = await dbHelper.getTasksByState(TransferState.transferring);
    var queuedTasks = await dbHelper.getTasksByState(TransferState.queued);
    
    expect(activeTasks.length, 2);
    expect(queuedTasks.length, 3);
    
    // Check that tasks 1 and 2 are the active ones
    expect(activeTasks.any((t) => t.id == 'task_1'), true);
    expect(activeTasks.any((t) => t.id == 'task_2'), true);

    // 3. Pause task 1 to free up a slot
    queueManager.pauseTask('task_1');
    
    // Wait for the transfer to cleanly abort and queue manager to process the next one
    await Future.delayed(const Duration(milliseconds: 500));
    
    // 4. Verify that task 3 began transferring automatically
    activeTasks = await dbHelper.getTasksByState(TransferState.transferring);
    var pausedTasks = await dbHelper.getTasksByState(TransferState.paused);
    queuedTasks = await dbHelper.getTasksByState(TransferState.queued);
    
    expect(pausedTasks.length, 1);
    expect(pausedTasks.first.id, 'task_1');
    
    expect(activeTasks.length, 2);
    expect(activeTasks.any((t) => t.id == 'task_2'), true);
    expect(activeTasks.any((t) => t.id == 'task_3'), true); // Task 3 picked up!
    
    expect(queuedTasks.length, 2); // Task 4 and 5 remain

    // Cleanup
    server.close();
    for (int i = 1; i <= 5; i++) {
      if (File('test_file_$i.bin').existsSync()) {
        File('test_file_$i.bin').deleteSync();
      }
    }
  });
}
