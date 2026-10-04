import 'dart:math';
import 'package:flutter/material.dart';
import '../models/transfer_task.dart';

class TransferListItem extends StatelessWidget {
  final TransferTask task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;
  final VoidCallback? onDownload;

  const TransferListItem({
    Key? key,
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    this.onDownload,
  }) : super(key: key);

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    double progress = task.totalBytes > 0 ? task.bytesTransferred / task.totalBytes : 0;
    
    String stateText = task.state.name.toUpperCase();
    Color stateColor = Colors.grey;
    IconData statusIcon = Icons.help_outline;

    if (task.state == TransferState.transferring) {
      stateColor = Colors.orange;
      statusIcon = Icons.cloud_upload_outlined;
    } else if (task.state == TransferState.completed) {
      stateColor = Colors.green;
      statusIcon = Icons.check_circle_outline;
    } else if (task.state == TransferState.failed) {
      stateColor = Colors.redAccent;
      statusIcon = Icons.error_outline;
    } else if (task.state == TransferState.paused) {
      stateColor = Colors.orangeAccent;
      statusIcon = Icons.pause_circle_outline;
    } else if (task.state == TransferState.queued) {
      stateColor = Colors.blueGrey;
      statusIcon = Icons.schedule;
    }

    final String filename = task.filePath.split('/').last.split('\\').last;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {}, // Ripple effect for accessibility
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(statusIcon, color: stateColor, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          filename,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_formatBytes(task.bytesTransferred)} of ${_formatBytes(task.totalBytes)} • ${task.speed > 0 ? '${_formatBytes(task.speed.round())}/s • ' : ''}$stateText',
                          style: TextStyle(fontSize: 13, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Animated Action Buttons
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _buildActionButtons(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Smooth Progress Bar and Pikachu
              LayoutBuilder(
                builder: (context, constraints) {
                  double pikachuWidth = 64.0;
                  double leftPosition = progress * (constraints.maxWidth - pikachuWidth);
                  
                  if (leftPosition < 0.0) leftPosition = 0.0;
                  if (leftPosition > constraints.maxWidth - pikachuWidth) {
                    leftPosition = constraints.maxWidth - pikachuWidth;
                  }

                  String pikachuImage = 'assets/pikachu_run.png';
                  if (task.state == TransferState.completed) {
                    pikachuImage = 'assets/pikachu_still.png';
                    leftPosition = constraints.maxWidth - pikachuWidth;
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 64.0,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: TweenAnimationBuilder<double>(
                                tween: Tween<double>(begin: 0, end: progress),
                                duration: const Duration(milliseconds: 500),
                                builder: (context, value, _) {
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      value: value,
                                      color: stateColor,
                                      backgroundColor: stateColor.withOpacity(0.15),
                                      minHeight: 8,
                                    ),
                                  );
                                },
                              ),
                            ),
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                              left: leftPosition,
                              bottom: 8.0, // Just above the progress bar
                              child: Image.asset(
                                pikachuImage,
                                width: pikachuWidth,
                                height: 56.0,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      key: ValueKey(task.state),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (task.state == TransferState.transferring)
          IconButton(
            icon: const Icon(Icons.pause, color: Colors.orangeAccent),
            onPressed: onPause,
            tooltip: 'Pause',
            splashRadius: 24,
          ),
        if (task.state == TransferState.paused || task.state == TransferState.failed)
          IconButton(
            icon: const Icon(Icons.play_arrow, color: Colors.green),
            onPressed: onResume,
            tooltip: 'Resume',
            splashRadius: 24,
          ),
        if (task.state != TransferState.completed)
          IconButton(
            icon: const Icon(Icons.close, color: Colors.redAccent),
            onPressed: onCancel,
            tooltip: 'Cancel',
            splashRadius: 24,
          ),
        if (task.state == TransferState.completed && !task.isDownload && onDownload != null)
          IconButton(
            icon: const Icon(Icons.download, color: Colors.orange),
            onPressed: onDownload,
            tooltip: 'Download File',
            splashRadius: 24,
          ),
        if (task.state == TransferState.completed)
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.grey),
            onPressed: onCancel,
            tooltip: 'Clear',
            splashRadius: 24,
          ),
      ],
    );
  }
}
