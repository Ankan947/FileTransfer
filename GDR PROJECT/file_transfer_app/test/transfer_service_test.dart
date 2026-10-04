import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/models/transfer_task.dart';
import '../lib/helpers/database_helper.dart';
import '../lib/services/transfer_service.dart';

void main() {
  test('Chunked download with pause and resume', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final int port = server.port;
    final int totalSize = 50 * 1024 * 1024; // 50MB
    int requestsHandled = 0;
    
    server.listen((HttpRequest request) {
      if (request.uri.path == '/download') {
        requestsHandled++;
        String? rangeHeader = request.headers.value('range');
        int start = 0;
        int end = totalSize - 1;

        if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
          final parts = rangeHeader.substring(6).split('-');
          if (parts.isNotEmpty && parts[0].isNotEmpty) {
            start = int.parse(parts[0]);
          }
          if (parts.length > 1 && parts[1].isNotEmpty) {
            end = int.parse(parts[1]);
          }
        }

        int chunkLength = end - start + 1;
        request.response.statusCode = 206;
        request.response.headers.add('content-length', chunkLength.toString());
        request.response.headers.add('content-range', 'bytes $start-$end/$totalSize');
        
        List<int> chunkData = List<int>.generate(chunkLength, (i) => (start + i) % 256);
        request.response.add(chunkData);
        request.response.close();
      } else {
        request.response.statusCode = 404;
        request.response.close();
      }
    });

    String downloadPath = 'test_download.bin';
    if (File(downloadPath).existsSync()) {
      File(downloadPath).deleteSync();
    }

    TransferTask task = TransferTask(
      id: 'task_1',
      url: 'http://localhost:$port/download',
      filePath: downloadPath,
      isDownload: true,
      totalBytes: totalSize,
    );

    await DatabaseHelper().saveTask(task);

    // 10MB chunks to trigger pause after 30MB
    TransferService service = TransferService(chunkSize: 10 * 1024 * 1024);

    bool paused = false;
    Future downloadFuture = service.startDownload(task);
    
    while (task.bytesTransferred < (totalSize / 2)) {
      await Future.delayed(Duration(milliseconds: 50));
    }
    
    if (!paused) {
      service.pause(task.id);
      paused = true;
    }

    await downloadFuture;

    expect(task.state, TransferState.paused);
    int pausedOffset = task.bytesTransferred;
    expect(pausedOffset, greaterThanOrEqualTo(totalSize / 2));
    
    int fileSizeAtPause = File(downloadPath).lengthSync();
    expect(fileSizeAtPause, pausedOffset);

    int initialRequests = requestsHandled;

    // Resume download
    await service.startDownload(task);

    expect(task.state, TransferState.completed);
    expect(task.bytesTransferred, totalSize);
    
    int finalFileSize = File(downloadPath).lengthSync();
    expect(finalFileSize, totalSize);

    List<int> finalFileBytes = File(downloadPath).readAsBytesSync();
    for (int i = 0; i < totalSize; i++) {
      if (finalFileBytes[i] != i % 256) {
        fail('Data corruption at byte $i');
      }
    }

    expect(requestsHandled, greaterThan(initialRequests));

    server.close();
    if (File(downloadPath).existsSync()) {
      File(downloadPath).deleteSync();
    }
  });
}
