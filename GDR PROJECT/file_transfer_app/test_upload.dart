import 'dart:io';
import 'package:dio/dio.dart';

void main() async {
  try {
    var file = File('test_2MB.bin');
    int totalBytes = await file.length();
    int chunkSize = 1024 * 1024;
    int startOffset = 0;
    
    Dio dio = Dio();

    while (startOffset < totalBytes) {
      int endOffset = startOffset + chunkSize;
      if (endOffset > totalBytes) endOffset = totalBytes;
      int length = endOffset - startOffset;
      
      FormData formData = FormData.fromMap({
          "file_id": "test_id_large",
          "chunk_index": (startOffset / chunkSize).floor().toString(),
          "total_chunks": (totalBytes / chunkSize).ceil().toString(),
          "original_name": "test_2MB.bin",
          "total_size": totalBytes.toString(),
          "file": MultipartFile.fromStream(() => file.openRead(startOffset, endOffset), length, filename: "chunk"),
      });

      print("Sending chunk ${startOffset / chunkSize}...");
      Response response = await dio.post(
          'http://127.0.0.1:5000/upload-chunk',
          data: formData,
      );
      print("Response: ${response.statusCode}");
      startOffset += length;
    }
  } catch (e) {
      print("Error: $e");
  }
}
