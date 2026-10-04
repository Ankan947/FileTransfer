import 'dart:io';
import 'package:dio/dio.dart';
import '../models/transfer_task.dart';
import '../helpers/database_helper.dart';

class TransferService {
  static final TransferService _instance = TransferService._internal();
  factory TransferService({Dio? dio, int chunkSize = 1024 * 1024}) {
    if (dio != null) _instance.dio = dio;
    _instance.chunkSize = chunkSize;
    return _instance;
  }
  
  TransferService._internal() : dio = Dio();

  Dio dio;
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final Map<String, CancelToken> _cancelTokens = {};
  
  int chunkSize = 1024 * 1024;

  Future<void> startDownload(TransferTask task) async {
    int startOffset = task.bytesTransferred;
    int totalBytes = task.totalBytes;
    String fileId = task.id;
    
    _cancelTokens[fileId] = CancelToken();
    CancelToken cancelToken = _cancelTokens[fileId]!;

    task.state = TransferState.transferring;
    await _dbHelper.updateProgress(fileId, startOffset, task.state);

    RandomAccessFile? raf;
    double currentSpeed = 0.0;

    try {
      raf = await File(task.filePath).open(mode: FileMode.append);
      while (startOffset < totalBytes) {
        if (cancelToken.isCancelled) break;

        int endOffset = startOffset + chunkSize - 1;
        if (endOffset >= totalBytes) endOffset = totalBytes - 1;

        DateTime chunkStart = DateTime.now();

        Response<List<int>> response = await dio.get<List<int>>(
          task.url,
          options: Options(
            headers: {'Range': 'bytes=$startOffset-$endOffset'},
            responseType: ResponseType.bytes,
          ),
          cancelToken: cancelToken,
        );

        if (response.statusCode == 206 || response.statusCode == 200) {
          List<int> chunkData = response.data!;
          await raf.writeFrom(chunkData);
          startOffset += chunkData.length;
          
          int durationMs = DateTime.now().difference(chunkStart).inMilliseconds;
          if (durationMs > 0) {
            double calcSpeed = (chunkData.length / durationMs) * 1000;
            currentSpeed = currentSpeed == 0.0 ? calcSpeed : (currentSpeed * 0.5 + calcSpeed * 0.5);
          }

          await _dbHelper.updateProgress(fileId, startOffset, TransferState.transferring, speed: currentSpeed);
        } else {
          throw Exception("Server responded with ${response.statusCode}");
        }
      }
      
      if (!cancelToken.isCancelled) {
        await _dbHelper.updateProgress(fileId, totalBytes, TransferState.completed, speed: 0);
      } else {
        await _dbHelper.updateProgress(fileId, startOffset, TransferState.paused, speed: 0);
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        await _dbHelper.updateProgress(fileId, startOffset, TransferState.paused, speed: 0);
      } else {
        print('DioException in startDownload: $e');
        await _dbHelper.updateProgress(fileId, startOffset, TransferState.failed, speed: 0);
      }
    } catch (e) {
      print('Exception in startDownload: $e');
      await _dbHelper.updateProgress(fileId, startOffset, TransferState.failed, speed: 0);
    } finally {
      if (raf != null) await raf.close();
      _cancelTokens.remove(fileId);
    }
  }

  Future<void> startUpload(TransferTask task) async {
    int startOffset = task.bytesTransferred;
    int totalBytes = task.totalBytes;
    String fileId = task.id;
    
    _cancelTokens[fileId] = CancelToken();
    CancelToken cancelToken = _cancelTokens[fileId]!;

    task.state = TransferState.transferring;
    await _dbHelper.updateProgress(fileId, startOffset, task.state);

    File file = File(task.filePath);
    if (!await file.exists()) {
       await _dbHelper.updateProgress(fileId, startOffset, TransferState.failed);
       return;
    }
    double currentSpeed = 0.0;

    try {
      while (startOffset < totalBytes) {
        if (cancelToken.isCancelled) break;

        int endOffset = startOffset + chunkSize;
        if (endOffset > totalBytes) endOffset = totalBytes;

        int length = endOffset - startOffset;
        Stream<List<int>> chunkStream = file.openRead(startOffset, endOffset);

        FormData formData = FormData.fromMap({
          "file_id": task.id,
          "chunk_index": (startOffset / chunkSize).floor().toString(),
          "total_chunks": (totalBytes / chunkSize).ceil().toString(),
          "original_name": file.path.split(Platform.pathSeparator).last,
          "total_size": totalBytes.toString(),
          "file": MultipartFile.fromStream(() => file.openRead(startOffset, endOffset), length, filename: "chunk"),
        });

        DateTime chunkStart = DateTime.now();

        Response response = await dio.post(
          task.url,
          data: formData,
          cancelToken: cancelToken,
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          startOffset += length;
          
          int durationMs = DateTime.now().difference(chunkStart).inMilliseconds;
          if (durationMs > 0) {
            double calcSpeed = (length / durationMs) * 1000;
            currentSpeed = currentSpeed == 0.0 ? calcSpeed : (currentSpeed * 0.5 + calcSpeed * 0.5);
          }

          await _dbHelper.updateProgress(fileId, startOffset, TransferState.transferring, speed: currentSpeed);
        } else {
          throw Exception("Server responded with ${response.statusCode}");
        }
      }

      if (!cancelToken.isCancelled) {
        await _dbHelper.updateProgress(fileId, totalBytes, TransferState.completed, speed: 0);
      } else {
        await _dbHelper.updateProgress(fileId, startOffset, TransferState.paused, speed: 0);
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        await _dbHelper.updateProgress(fileId, startOffset, TransferState.paused, speed: 0);
      } else {
        await _dbHelper.updateProgress(fileId, startOffset, TransferState.failed, speed: 0);
      }
    } catch (e) {
      await _dbHelper.updateProgress(fileId, startOffset, TransferState.failed, speed: 0);
    } finally {
      _cancelTokens.remove(fileId);
    }
  }

  void pause(String fileId) {
    if (_cancelTokens.containsKey(fileId)) {
      _cancelTokens[fileId]!.cancel("Paused by user");
    }
  }

  void resume(TransferTask task) {
    if (task.isDownload) {
      startDownload(task);
    } else {
      startUpload(task);
    }
  }

  void cancel(String fileId) {
    if (_cancelTokens.containsKey(fileId)) {
      _cancelTokens[fileId]!.cancel("Cancelled by user");
    }
    _dbHelper.updateProgress(fileId, 0, TransferState.failed);
  }
}
