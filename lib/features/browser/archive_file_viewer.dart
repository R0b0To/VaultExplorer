import 'dart:io';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';

class ArchiveFileViewer extends StatefulWidget {
  final File file;
  final String fileName;

  const ArchiveFileViewer({super.key, required this.file, required this.fileName});

  @override
  State<ArchiveFileViewer> createState() => _ArchiveFileViewerState();
}

class _ArchiveFileViewerState extends State<ArchiveFileViewer> {
  @override
  void dispose() {
    // Clean up the temporary file when closed
    try {
      if (widget.file.existsSync()) {
        widget.file.deleteSync();
      }
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ext = widget.fileName.contains('.') ? widget.fileName.split('.').last.toLowerCase() : '';
    final isImage = MediaViewerConstants.isImage(widget.fileName);
    final isText = const {'txt', 'md', 'csv', 'json', 'xml'}.contains(ext);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
        elevation: 0,
      ),
      body: Center(
        child: _buildContent(isImage, isText),
      ),
    );
  }

  Widget _buildContent(bool isImage, bool isText) {
    if (isImage) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Image.file(widget.file),
      );
    }
    
    if (isText) {
      return FutureBuilder<String>(
        future: widget.file.readAsString(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const CircularProgressIndicator();
          }
          if (snapshot.hasError) {
            return Text('Error reading file: ${snapshot.error}');
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: SelectableText(
                snapshot.data ?? '',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          );
        },
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.insert_drive_file_outlined, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Text(
          'Preview not available for this file type.',
          style: TextStyle(color: Colors.grey[600]),
        ),
      ],
    );
  }
}
