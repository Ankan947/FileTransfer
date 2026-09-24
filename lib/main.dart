import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Resumable Transfer',
      theme: ThemeData(brightness: Brightness.dark, primarySwatch: Colors.blue),
      home: const TransferQueueScreen(),
    );
  }
}

class TransferQueueScreen extends StatefulWidget {
  const TransferQueueScreen({super.key});

  @override
  State<TransferQueueScreen> createState() => _TransferQueueScreenState();
}

class _TransferQueueScreenState extends State<TransferQueueScreen> {
  List<Map<String, dynamic>> transfers = [];
  SharedPreferences? prefs;
  final String serverUrl = 'http://127.0.0.1:5000';

  @override
  void initState() {
    super.initState();
    _loadSavedTransfers();
  }

  Future<void> _loadSavedTransfers() async {
    prefs = await SharedPreferences.getInstance();
    String? savedData = prefs?.getString('transfer_queue');
    if (savedData != null) {
      setState(() {
        transfers = List<Map<String, dynamic>>.from(json.decode(savedData));
        for (var t in transfers) {
          if (t['state'] == 'TRANSFERRING') t['state'] = 'PAUSED';
        }
      });
    }
  }

  Future<void> _saveTransfers() async {
    if (prefs != null) {
      var dataToSave = transfers.map((t) {
        return {
          'id': t['id'],
          'name': t['name'],
          'size': t['size'],
          'progress': t['progress'],
          'state': t['state'],
          'type': t['type'],
          'error': t['error']
        };
      }).toList();
      await prefs?.setString('transfer_queue', json.encode(dataToSave));
    }
  }

  // --- UPLOAD LOGIC ---
  void pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(withData: true); 
    if (result != null) {
      setState(() {
        transfers.add({
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'name': result.files.first.name,
          'size': result.files.first.size,
          'progress': 0.0,
          'state': 'QUEUED',
          'type': 'Upload',
          'error': '',
          'bytes': result.files.first.bytes, 
        });
      });
      _saveTransfers();
    }
  }

  Future<void> _startUpload(int index) async {
    var transfer = transfers[index];
    if (transfer['bytes'] == null) {
      setState(() {
        transfers[index]['state'] = 'FAILED';
        transfers[index]['error'] = 'File data lost. Please re-queue.';
      });
      return;
    }

    Uint8List fileBytes = transfer['bytes'];
    int chunkSize = 1024 * 1024; // 1 MB
    int totalChunks = (fileBytes.length / chunkSize).ceil();
    int currentChunk = (transfer['progress'] * totalChunks).floor();
    int currentRetry = 0;

    while (currentChunk < totalChunks && transfers[index]['state'] == 'TRANSFERRING') {
      int start = currentChunk * chunkSize;
      int end = (start + chunkSize < fileBytes.length) ? start + chunkSize : fileBytes.length;
      List<int> chunkData = fileBytes.sublist(start, end);

      var request = http.MultipartRequest('POST', Uri.parse('$serverUrl/upload-chunk'));
      request.fields['file_id'] = transfer['id'];
      request.fields['chunk_index'] = currentChunk.toString();
      request.fields['total_chunks'] = totalChunks.toString();
      request.fields['original_name'] = transfer['name'];
      request.fields['total_size'] = transfer['size'].toString();
      request.files.add(http.MultipartFile.fromBytes('file', chunkData, filename: 'part'));

      try {
        var response = await request.send();
        if (response.statusCode == 200) {
          currentChunk++;
          currentRetry = 0;
          if (mounted) {
            setState(() {
              transfers[index]['progress'] = currentChunk / totalChunks;
              if (currentChunk >= totalChunks) transfers[index]['state'] = 'COMPLETED';
            });
            _saveTransfers();
          }
        } else {
          throw Exception("Server error");
        }
      } catch (e) {
        currentRetry++;
        if (currentRetry >= 3) {
          if (mounted) {
            setState(() {
              transfers[index]['state'] = 'FAILED';
              transfers[index]['error'] = 'Network disconnected.';
            });
            _saveTransfers();
          }
          break;
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  // --- DOWNLOAD LOGIC ---
  Future<void> _fetchServerFiles() async {
    try {
      var response = await http.get(Uri.parse('$serverUrl/list-files'));
      if (response.statusCode == 200) {
        List files = json.decode(response.body);
        _showDownloadDialog(files);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Server offline.')));
    }
  }

  void _showDownloadDialog(List files) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Server Files (Ready to Download)'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: files.length,
            itemBuilder: (context, index) {
              return ListTile(
                leading: const Icon(Icons.file_download),
                title: Text(files[index]['name']),
                subtitle: Text('${(files[index]['size'] / 1024 / 1024).toStringAsFixed(2)} MB'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    transfers.add({
                      'id': DateTime.now().millisecondsSinceEpoch.toString(),
                      'name': files[index]['name'],
                      'size': files[index]['size'],
                      'progress': 0.0,
                      'state': 'QUEUED',
                      'type': 'Download',
                      'error': '',
                    });
                  });
                  _saveTransfers();
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _startDownload(int index) async {
    var transfer = transfers[index];
    int chunkSize = 1024 * 1024;
    int totalChunks = (transfer['size'] / chunkSize).ceil();
    int currentChunk = (transfer['progress'] * totalChunks).floor();
    int currentRetry = 0;

    while (currentChunk < totalChunks && transfers[index]['state'] == 'TRANSFERRING') {
      try {
        var response = await http.get(Uri.parse('$serverUrl/download-chunk?filename=${transfer['name']}&chunk_index=$currentChunk'));
        if (response.statusCode == 200) {
          currentChunk++;
          currentRetry = 0;
          if (mounted) {
            setState(() {
              transfers[index]['progress'] = currentChunk / totalChunks;
              if (currentChunk >= totalChunks) transfers[index]['state'] = 'COMPLETED';
            });
            _saveTransfers();
          }
        } else {
          throw Exception("Server error");
        }
      } catch (e) {
        currentRetry++;
        if (currentRetry >= 3) {
          if (mounted) {
            setState(() {
              transfers[index]['state'] = 'FAILED';
              transfers[index]['error'] = 'Network disconnected.';
            });
            _saveTransfers();
          }
          break;
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  // --- GENERAL CONTROLS ---
  void togglePause(int index) {
    setState(() {
      if (transfers[index]['state'] == 'TRANSFERRING') {
        transfers[index]['state'] = 'PAUSED';
      } else {
        transfers[index]['state'] = 'TRANSFERRING';
        transfers[index]['error'] = ''; 
        if (transfers[index]['type'] == 'Upload') {
          _startUpload(index);
        } else {
          _startDownload(index);
        }
      }
    });
    _saveTransfers();
  }

  void cancelTransfer(int index) {
    setState(() => transfers.removeAt(index));
    _saveTransfers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resumable Transfers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_download),
            tooltip: 'Download from Server',
            onPressed: _fetchServerFiles,
          )
        ],
      ),
      body: transfers.isEmpty
          ? const Center(child: Text('No active transfers. Click + to add.'))
          : ListView.builder(
              itemCount: transfers.length,
              itemBuilder: (context, index) {
                var transfer = transfers[index];
                Color typeColor = transfer['type'] == 'Upload' ? Colors.blueAccent : Colors.green;
                
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text(transfer['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: typeColor, borderRadius: BorderRadius.circular(12)),
                              child: Text(transfer['type'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            )
                          ],
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(value: transfer['progress'], color: typeColor),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Status: ${transfer['state']}'),
                            Row(
                              children: [
                                if (transfer['state'] != 'COMPLETED')
                                  IconButton(
                                    icon: Icon(transfer['state'] == 'TRANSFERRING' ? Icons.pause : (transfer['state'] == 'FAILED' ? Icons.refresh : Icons.play_arrow)),
                                    onPressed: () => togglePause(index),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.cancel, color: Colors.redAccent),
                                  onPressed: () => cancelTransfer(index),
                                ),
                              ],
                            )
                          ],
                        ),
                        if (transfer['error'] != null && transfer['error'].toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(transfer['error'], style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                          )
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: pickFile,
        child: const Icon(Icons.add),
      ),
    );
  }
}