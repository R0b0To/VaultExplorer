import 'package:flutter/material.dart';

class FormatUtils {
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int idx = 0;
    while (size >= 1024 && idx < suffixes.length - 1) {
      size /= 1024;
      idx++;
    }
    return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${suffixes[idx]}';
  }

  static IconData iconForFile(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Icons.image_outlined;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
      case 'webm':
        return Icons.ondemand_video_outlined;
      case 'mp3':
      case 'flac':
      case 'wav':
      case 'm4a':
        return Icons.audio_file_outlined;
      case 'txt':
      case 'md':
      case 'csv':
        return Icons.article_outlined;
      case 'zip':
      case 'gz':
      case 'tar':
      case '7z':
        return Icons.archive_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  static Color colorForFile(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return const Color(0xFFEF5350);
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return const Color(0xFF26C6DA);
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
      case 'webm':
        return const Color(0xFF7E57C2);
      case 'mp3':
      case 'flac':
      case 'wav':
      case 'm4a':
        return const Color(0xFF66BB6A);
      case 'txt':
      case 'md':
      case 'csv':
        return const Color(0xFF78909C);
      default:
        return const Color(0xFF546E7A);
    }
  }
}