import 'dart:io';
import 'dart:async'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:video_player/video_player.dart';
import '../../models/mounted_container.dart';
import '../../services/cryptbridge_api.dart';

class MediaViewerScreen extends StatefulWidget {
  final MountedContainer container;
  final List<String> mediaFiles;
  final int initialIndex;

  const MediaViewerScreen({
    Key? key,
    required this.container,
    required this.mediaFiles,
    required this.initialIndex,
  }) : super(key: key);

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showUI = true;
  bool _isLandscape = false; 

  _LocalStreamingServer? _streamingServer;
  int? _serverPort;
  bool _serverReady = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _startServer();
  }

  Future<void> _startServer() async {
    _streamingServer = _LocalStreamingServer(widget.container);
    final port = await _streamingServer!.start();
    if (mounted) {
      setState(() {
        _serverPort = port;
        _serverReady = true;
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _streamingServer?.stop();
    
    // Safety Restorations
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _setUIVisibility(bool show) {
    if (mounted) {
      setState(() {
        _showUI = show;
      });
      if (show) {
         SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    }
  }

  void _toggleOrientation() {
    setState(() {
      _isLandscape = !_isLandscape;
    });
    if (_isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  Future<void> _exportCurrentFile() async {
    final fileName = widget.mediaFiles[_currentIndex];
    final publicDownloads = Directory('/storage/emulated/0/Download');
    if (!await publicDownloads.exists()) {
      await publicDownloads.create(recursive: true);
    }
    final destPath = '${publicDownloads.path}/$fileName';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exporting $fileName…')),
    );

    try {
      final success = await CryptBridgeApi.decryptFile(
        widget.container,
        fileName,
        destPath,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? 'Saved to Downloads/$fileName'
                : 'Export failed'),
            backgroundColor: success ? const Color(0xFF1A3A2A) : null,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_serverReady) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4FC3F7)),
          ),
        ),
      );
    }

    final total = widget.mediaFiles.length;
    final currentName = widget.mediaFiles[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Media Swiper
          PageView.builder(
            controller: _pageController,
            itemCount: total,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              final streamUrl = 'http://127.0.0.1:$_serverPort/media?file=${widget.mediaFiles[index]}';
              return _MediaPage(
                fileName: widget.mediaFiles[index],
                streamUrl: streamUrl,
                showUI: _showUI,
                onToggleUI: _setUIVisibility, 
              );
            },
          ),

          // Top Immersive Bar
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            top: _showUI ? 0 : -100,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                bottom: 12,
                left: 8,
                right: 8,
              ),
              color: Colors.black.withOpacity(0.7),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentName.split('/').last,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_currentIndex + 1} of $total',
                          style: const TextStyle(
                            color: Color(0xFF7A8899),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _isLandscape ? Icons.screen_lock_portrait : Icons.screen_rotation,
                      color: Colors.white,
                    ),
                    tooltip: 'Toggle Fullscreen Rotation',
                    onPressed: _toggleOrientation,
                  ),
                  IconButton(
                    icon: const Icon(Icons.download_outlined, color: Colors.white),
                    tooltip: 'Export to Downloads',
                    onPressed: _exportCurrentFile,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaPage extends StatelessWidget {
  final String fileName;
  final String streamUrl;
  final bool showUI;
  final ValueChanged<bool> onToggleUI;

  const _MediaPage({
    Key? key,
    required this.fileName,
    required this.streamUrl,
    required this.showUI,
    required this.onToggleUI,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final ext = fileName.split('.').last.toLowerCase();
    final isImg = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);

    return Container(
      color: Colors.black,
      child: isImg
          ? GestureDetector(
              onTap: () => onToggleUI(!showUI), 
              child: InteractiveViewer(
                maxScale: 4.0,
                child: Center(
                  child: Image.network(
                    streamUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Text('Failed to stream image.', style: TextStyle(color: Colors.red)),
                    ),
                  ),
                ),
              ),
            )
          : RealVideoPlayerWidget(
              streamUrl: streamUrl,
              showUI: showUI,
              onToggleUI: onToggleUI,
            ),
    );
  }
}

// ─────────────────────────────────────────────
// Real Video Player with Auto-Hiding Seek Bar
// ─────────────────────────────────────────────

class RealVideoPlayerWidget extends StatefulWidget {
  final String streamUrl;
  final bool showUI;
  final ValueChanged<bool> onToggleUI;

  const RealVideoPlayerWidget({
    Key? key,
    required this.streamUrl,
    required this.showUI,
    required this.onToggleUI,
  }) : super(key: key);

  @override
  State<RealVideoPlayerWidget> createState() => _RealVideoPlayerWidgetState();
}

class _RealVideoPlayerWidgetState extends State<RealVideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  String? _playerError;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _sliderValue = 0.0;
  bool _isDragging = false;

  Timer? _hideTimer;
  DateTime _lastSeekTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.streamUrl));
    } catch (e) {
      _controller = VideoPlayerController.network(widget.streamUrl);
    }
    
    _controller.addListener(() {
      if (_controller.value.hasError) {
        if (mounted) {
          setState(() {
            _playerError = _controller.value.errorDescription ?? "ExoPlayer stream error.";
          });
        }
        return;
      }

      if (mounted && _initialized) {
        setState(() {
          _position = _controller.value.position;
          _duration = _controller.value.duration;
          
          if (!_isDragging && _duration.inMilliseconds > 0) {
            _sliderValue = _position.inMilliseconds / _duration.inMilliseconds;
          }
        });
      }
    });

    try {
      await _controller.initialize();
      if (mounted) {
        setState(() {
          _initialized = true;
          _duration = _controller.value.duration;
        });
        _controller.play();
        _startHideTimer(); 
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _playerError = "Stream initialization failed: $e";
        });
      }
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    if (_initialized) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying && widget.showUI) {
        widget.onToggleUI(false); 
      }
    });
  }

  void _showControlsAndResetTimer() {
    if (!widget.showUI) {
      widget.onToggleUI(true); 
    }
    _startHideTimer();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    if (_playerError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFEF5350), size: 36),
              const SizedBox(height: 12),
              Text(
                _playerError!,
                style: const TextStyle(color: Color(0xFFEF5350), fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (!_initialized) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4FC3F7)),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;

    return ClipRect(
      // Clips horizontally strictly to the phone's left & right boundaries,
      // but allows the video to expand vertically all the way to the top and bottom of the screen [1.1.4].
      child: Stack(
        clipBehavior: Clip.none, // Allows elements to animate off-screen without clipping the main canvas
        alignment: Alignment.center,
        children: [
          // Full-screen InteractiveViewer for zoom-to-fill capability [5]
          InteractiveViewer(
            maxScale: 6.0,
            minScale: 1.0,
            clipBehavior: Clip.none, // Allows the video to expand past standard aspect-ratio bounds [1.1.4]
            child: Center(
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: GestureDetector(
                  onTap: () {
                    widget.onToggleUI(!widget.showUI); 
                    if (!widget.showUI) {
                      _startHideTimer();
                    }
                  },
                  child: VideoPlayer(_controller),
                ),
              ),
            ),
          ),

          // Auto-Hiding Seekbar Control Panel (Now positioned relative to the screen bottom)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            left: 0,
            right: 0,
            bottom: widget.showUI ? 0 : -100, // Moves out of view below the screen boundary
            child: Container(
              padding: EdgeInsets.only(
                top: 8,
                bottom: MediaQuery.of(context).padding.bottom + 8,
                left: 16,
                right: 16,
              ),
              color: Colors.black.withOpacity(0.6),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: () {
                      _showControlsAndResetTimer();
                      setState(() {
                        _controller.value.isPlaying ? _controller.pause() : _controller.play();
                      });
                    },
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatDuration(_position),
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFF4FC3F7),
                        inactiveTrackColor: const Color(0xFF2A3040),
                        thumbColor: const Color(0xFF4FC3F7),
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      ),
                      child: Slider(
                        value: _sliderValue.clamp(0.0, 1.0),
                        onChanged: (value) {
                          _showControlsAndResetTimer();
                          setState(() {
                            _isDragging = true;
                            _sliderValue = value;
                          });
                          
                          // Throttled seeking to update video frames instantly while scrubbing
                          final now = DateTime.now();
                          if (now.difference(_lastSeekTime).inMilliseconds > 100) {
                            _lastSeekTime = now;
                            final targetMs = (value * _duration.inMilliseconds).toInt();
                            _controller.seekTo(Duration(milliseconds: targetMs));
                          }
                        },
                        onChangeEnd: (value) {
                          final targetMs = (value * _duration.inMilliseconds).toInt();
                          _controller.seekTo(Duration(milliseconds: targetMs)).then((_) {
                            setState(() {
                              _isDragging = false;
                            });
                            _startHideTimer();
                          });
                        },
                      ),
                    ),
                  ),
                  Text(
                    _formatDuration(_duration),
                    style: const TextStyle(color: Color(0xFF7A8899), fontSize: 11),
                  ),
                ],
              ),
            ),
          ),

          // Large Center Play/Pause Indicator
          if (widget.showUI)
            Center(
              child: GestureDetector(
                onTap: () {
                  _showControlsAndResetTimer();
                  setState(() {
                    _controller.value.isPlaying ? _controller.pause() : _controller.play();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LocalStreamingServer {
  HttpServer? _server;
  final MountedContainer container;

  _LocalStreamingServer(this.container);

  Future<int> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleRequest);
    return _server!.port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
  }

  void _handleRequest(HttpRequest request) async {
    try {
      if (request.method != 'GET') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }

      final fileName = request.uri.queryParameters['file'];
      if (fileName == null) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }

      final fileSize = await CryptBridgeApi.getFileSize(container, fileName);
      if (fileSize <= 0) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final headers = request.response.headers;
      headers.set(HttpHeaders.contentTypeHeader, _getMimeType(fileName));
      headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final parts = rangeHeader.substring(6).split('-');
        final start = int.tryParse(parts[0]) ?? 0;
        var end = parts.length > 1 && parts[1].isNotEmpty
            ? int.tryParse(parts[1]) ?? (fileSize - 1)
            : (fileSize - 1);

        if (end >= fileSize) {
          end = fileSize - 1;
        }

        final contentLength = end - start + 1;
        request.response.statusCode = HttpStatus.partialContent;
        headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$fileSize');
        headers.set(HttpHeaders.contentLengthHeader, contentLength.toString());

        var currentPosition = start;
        const chunkSize = 524288; // 512 KB packets

        while (currentPosition <= end) {
          final remaining = end - currentPosition + 1;
          final currentChunkSize = remaining < chunkSize ? remaining : chunkSize;

          final bytes = await CryptBridgeApi.readFileChunk(
            container,
            fileName,
            currentPosition,
            currentChunkSize,
          );

          if (bytes == null || bytes.isEmpty) {
            break; 
          }

          request.response.add(bytes);
          await request.response.flush();

          currentPosition += bytes.length;
        }
      } else {
        headers.set(HttpHeaders.contentLengthHeader, fileSize.toString());
        request.response.statusCode = HttpStatus.ok;

        var currentPosition = 0;
        const chunkSize = 131072;

        while (currentPosition < fileSize) {
          final remaining = fileSize - currentPosition;
          final currentChunkSize = remaining < chunkSize ? remaining : chunkSize;

          final bytes = await CryptBridgeApi.readFileChunk(
            container,
            fileName,
            currentPosition,
            currentChunkSize,
          );

          if (bytes == null || bytes.isEmpty) {
            break;
          }

          request.response.add(bytes);
          await request.response.flush();

          currentPosition += bytes.length;
        }
      }
    } catch (e, stack) {
      debugPrint('STREAM SERVER EXCEPTION: $e');
      debugPrint('$stack');
    } finally {
      try {
        await request.response.close();
      } catch (e) {
        // ignore
      }
    }
  }

  String _getMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp4':
      case 'm4v': return 'video/mp4';
      case 'webm': return 'video/webm'; // Added 'webm'
      case 'mkv': return 'video/x-matroska';
      case 'mov': return 'video/quicktime';
      case 'avi': return 'video/x-msvideo';
      case 'png': return 'image/png';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'webp': return 'image/webp';
      case 'gif': return 'image/gif';
      default: return 'application/octet-stream';
    }
  }
}