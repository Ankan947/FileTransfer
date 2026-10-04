import 'dart:io';
import 'package:dio/dio.dart';

void main() async {
  try {
    var file = File('test_1GB.bin');
    if (!file.existsSync()) {
        file.writeAsBytesSync(List.filled(100, 0));
    }
    var stream = () => file.openRead(0, 10);
    var mp = MultipartFile.fromStream(stream, 10, filename: "chunk");
    print("Success: ${mp.filename}");
  } catch (e) {
    print("Error: $e");
  }
}
