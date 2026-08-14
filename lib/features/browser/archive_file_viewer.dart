import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';


class ArchiveFileViewer extends StatelessWidget {
  final Uint8List bytes;
  final String fileName;

  const ArchiveFileViewer({super.key, required this.bytes, required this.fileName});

  @override
  Widget build(BuildContext context) {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    final isImage = MediaViewerConstants.isImage(fileName);
    final isText = const {'txt', 'md', 'csv', 'json', 'xml'}.contains(ext);

    return Scaffold(
      appBar: AppBar(
        title: Text(fileName),
        elevation: 0,
      ),
      body: Center(
        child: _buildContent(context, isImage, isText),
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool isImage, bool isText) {
    if (isImage) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Image.memory(bytes),
      );
    }

    if (isText) {
      String? text;
      Object? error;
      try {
        text = utf8.decode(bytes);
      } catch (e) {
        error = e;
      }

      if (error != null) {
        return Text(context.l10n.archiveErrorReadingFile('$error'));
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          width: double.infinity,
          child: SelectableText(
            text ?? '',
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.insert_drive_file_outlined, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Text(
          context.l10n.archivePreviewNotAvailableMessage,
          style: TextStyle(color: Colors.grey[600]),
        ),
      ],
    );
  }
}
