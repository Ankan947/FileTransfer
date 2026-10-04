enum TransferState { queued, transferring, completed, retrying, failed, paused }

class TransferTask {
  final String id;
  final String url;
  final String filePath;
  final bool isDownload;
  int bytesTransferred;
  final int totalBytes;
  TransferState state;
  double speed;

  TransferTask({
    required this.id,
    required this.url,
    required this.filePath,
    required this.isDownload,
    this.bytesTransferred = 0,
    required this.totalBytes,
    this.state = TransferState.queued,
    this.speed = 0.0,
  });
}
