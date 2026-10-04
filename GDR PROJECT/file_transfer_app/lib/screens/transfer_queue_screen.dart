import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../helpers/database_helper.dart';
import '../models/transfer_task.dart';
import '../services/queue_manager.dart';
import '../widgets/transfer_list_item.dart';

class TransferQueueScreen extends StatefulWidget {
  const TransferQueueScreen({Key? key}) : super(key: key);

  @override
  State<TransferQueueScreen> createState() => _TransferQueueScreenState();
}

class _TransferQueueScreenState extends State<TransferQueueScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final QueueManager _queueManager = QueueManager();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('File Manager', style: TextStyle(fontWeight: FontWeight.bold)),
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_forever),
              tooltip: 'Delete All Cloud Files',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete All Files'),
                    content: const Text('Are you sure you want to delete all files stored in cloud storage? This cannot be undone.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete All', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                
                if (confirm == true) {
                  try {
                    final response = await Dio().delete('http://127.0.0.1:5000/delete-all');
                    if (response.statusCode == 200) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All files deleted successfully')));
                      }
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete files: $e')));
                    }
                  }
                }
              },
            ),
          ],
          bottom: const TabBar(
            indicatorWeight: 3,
            tabs: [
              Tab(icon: Icon(Icons.upload_rounded), text: 'Uploads'),
              Tab(icon: Icon(Icons.download_rounded), text: 'Downloads'),
              Tab(icon: Icon(Icons.cloud), text: 'Cloud Storage'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _TransfersView(dbHelper: _dbHelper, queueManager: _queueManager, isDownloadView: false),
            _TransfersView(dbHelper: _dbHelper, queueManager: _queueManager, isDownloadView: true),
            _CloudFilesView(queueManager: _queueManager),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// TAB 1 & 2: ACTIVE TRANSFERS (Uploads / Downloads)
// ---------------------------------------------------------
class _TransfersView extends StatelessWidget {
  final DatabaseHelper dbHelper;
  final QueueManager queueManager;
  final bool isDownloadView;

  const _TransfersView({required this.dbHelper, required this.queueManager, required this.isDownloadView});

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(); 
    if (result != null && result.files.single.path != null) {
      final task = TransferTask(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        url: 'http://127.0.0.1:5000/upload-chunk',
        filePath: result.files.single.path!,
        isDownload: false,
        totalBytes: result.files.single.size,
      );
      await queueManager.enqueue(task);
    }
  }

  void _handlePause(String taskId) => queueManager.pauseTask(taskId);
  void _handleResume(TransferTask task) => queueManager.enqueue(task);
  
  Future<void> _handleCancel(TransferTask task) async {
    if (task.state == TransferState.transferring) {
      queueManager.pauseTask(task.id);
    }
    await dbHelper.deleteTask(task.id);
    try {
      final file = File(task.filePath);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint("Failed to delete file: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<TransferTask>>(
        stream: dbHelper.tasksStream,
        initialData: dbHelper.getAllTasksSync(),
        builder: (context, snapshot) {
          final allTasks = snapshot.data ?? [];
          final tasks = allTasks.where((t) => t.isDownload == isDownloadView).toList();

          // Sort tasks: active, queued, paused, failed, completed
          tasks.sort((a, b) {
            final order = {
              TransferState.transferring: 0,
              TransferState.retrying: 1,
              TransferState.queued: 2,
              TransferState.paused: 3,
              TransferState.failed: 4,
              TransferState.completed: 5,
            };
            return order[a.state]!.compareTo(order[b.state]!);
          });

          if (tasks.isEmpty) {
            return _buildEmptyState();
          }

              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 100), // Space for FAB
                itemCount: tasks.length,
                itemBuilder: (context, index) {
                  final task = tasks[index];
                  return TransferListItem(
                    task: task,
                    onPause: () => _handlePause(task.id),
                    onResume: () => _handleResume(task),
                    onCancel: () => _handleCancel(task),
                  );
                },
              );
            },
          ),
      floatingActionButton: !isDownloadView ? FloatingActionButton.extended(
        onPressed: _pickFile,
        icon: const Icon(Icons.upload_file),
        label: const Text('Upload File'),
      ) : null,
    );
  }

  Widget _buildEmptyState() {
    String title = isDownloadView ? 'No active downloads' : 'No active uploads';
    String subtitle = isDownloadView 
        ? 'Download files from the Cloud Storage tab' 
        : 'Click the Upload button below to get started';

    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: Opacity(
              opacity: value,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/pikachu.png', width: 100, height: 100, fit: BoxFit.contain),
                  const SizedBox(height: 16),
                  Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black54)),
                  const SizedBox(height: 8),
                  Text(subtitle, style: TextStyle(fontSize: 14, color: Colors.black87)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------
// TAB 2: CLOUD FILES (SERVER BROWSER)
// ---------------------------------------------------------
class _CloudFilesView extends StatefulWidget {
  final QueueManager queueManager;
  const _CloudFilesView({required this.queueManager});

  @override
  State<_CloudFilesView> createState() => _CloudFilesViewState();
}

class _CloudFilesViewState extends State<_CloudFilesView> {
  List<dynamic> _files = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchFiles();
  }

  Future<void> _fetchFiles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await Dio().get('http://127.0.0.1:5000/list-files');
      if (mounted) {
        setState(() {
          _files = response.data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Failed to connect to the server.";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _downloadFile(String filename, int size) async {
    String? destDirectory = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select where to save the file');
    if (destDirectory == null) return;

    String destPath = '$destDirectory${Platform.pathSeparator}$filename';

    final downloadTask = TransferTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: 'http://127.0.0.1:5000/download/${Uri.encodeComponent(filename)}',
      filePath: destPath,
      isDownload: true,
      totalBytes: size,
    );
    await widget.queueManager.enqueue(downloadTask);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$filename added to your Active Transfers queue!'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green,
        )
      );
      // Switch back to Downloads tab to show progress
      DefaultTabController.of(context).animateTo(1);
    }
  }

  Future<void> _deleteFile(String filename) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $filename?'),
        content: const Text('Are you sure you want to delete this file from the cloud?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    
    if (confirm == true) {
      try {
        final response = await Dio().delete('http://127.0.0.1:5000/delete/$filename');
        if (response.statusCode == 200) {
          _fetchFiles(); // refresh the list
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$filename deleted')));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchFiles,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            )
          ],
        ),
      );
    }

    if (_files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_queue, size: 80, color: Colors.orange),
            const SizedBox(height: 16),
            Text('Your cloud is empty', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black54)),
            const SizedBox(height: 8),
            Text('Upload some files first to see them here.', style: TextStyle(fontSize: 14, color: Colors.black87)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchFiles,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            )
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchFiles,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _files.length,
        itemBuilder: (context, index) {
          final file = _files[index];
          final sizeMB = (file['size'] / (1024 * 1024)).toStringAsFixed(2);
          
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8)
                    ),
                    child: const Icon(Icons.insert_drive_file, color: Colors.orange, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(file['name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text('$sizeMB MB', style: TextStyle(fontSize: 14, color: Colors.black54)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _downloadFile(file['name'], file['size']),
                    icon: const Icon(Icons.download),
                    label: const Text('Download', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    tooltip: 'Delete File',
                    onPressed: () => _deleteFile(file['name']),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
