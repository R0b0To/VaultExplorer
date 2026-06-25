import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../models/mounted_container.dart';
import '../../services/vaultexplorer_api.dart';
import '../../services/local_streaming_server.dart';// ── Playback preferences (local to this session) ──────────────────────────
  bool _autoPlay = true;
  bool _autoAdvance = false;
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

  late List<String> _originalList;
  late List<String> _currentPlaylist;
  bool _isShuffled = false;

  String _selectedFolder = 'Current Folder Only';
  int _doubleTapSkipSeconds = 5;

  bool _allFilesScanned = false;
  bool _isScanningSubfolders = false;

  ScrollPhysics _pagePhysics = const ClampingScrollPhysics();

  LocalStreamingServer? _streamingServer;
  int? _serverPort;
  bool _serverReady = false;
  String? _serverError;

  

  @override
  void initState() {
    super.initState();
    _originalList = List.from(widget.mediaFiles);
    _currentPlaylist = List.from(widget.mediaFiles);
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _startServer();
  }

  String _getBaseDir() {
    if (widget.mediaFiles.isEmpty) return '';
    final firstFile = widget.mediaFiles.first;
    if (!firstFile.contains('/')) return '';
    return firstFile.substring(0, firstFile.lastIndexOf('/'));
  }

  bool _isSupportedMedia(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp',
            'mp4', 'm4v', 'webm', 'mov', 'avi', 'mkv'].contains(ext);
  }

  Future<void> _loadRecursiveMedia() async {
    final baseDir = _getBaseDir();
    final recursiveFiles = await _scanDirectoryRecursively(baseDir);
    if (recursiveFiles.isEmpty) return;
    if (mounted) setState(() => _originalList = List.from(recursiveFiles));
  }

  Future<List<String>> _scanDirectoryRecursively(String baseDir) async {
    final foundFiles = <String>[];
    try {
      final items =
          await vaultExplorerApi.listDirectory(widget.container, baseDir);
      if (items != null) {
        for (final item in items) {
          if (item.startsWith('[DIR] ')) {
            final subDirName = item.replaceFirst('[DIR] ', '');
            final subDirPath =
                baseDir.isEmpty ? subDirName : '$baseDir/$subDirName';
            final nested = await _scanDirectoryRecursively(subDirPath);
            foundFiles.addAll(nested);
          } else if (!item.startsWith('System:')) {
            final fileName = item.split('|').first;
            if (_isSupportedMedia(fileName)) {
              final fullPath =
                  baseDir.isEmpty ? fileName : '$baseDir/$fileName';
              foundFiles.add(fullPath);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error walking subdirectories: $e');
    }
    return foundFiles;
  }

  void _applyFolderFiltering(String folder, String currentFile) {
    final baseDir = _getBaseDir();
    List<String> filteredList;
    if (folder == 'All') {
      filteredList = List.from(_originalList);
    } else {
      filteredList = _originalList.where((file) {
        final dir = file.contains('/')
            ? file.substring(0, file.lastIndexOf('/'))
            : '';
        return dir == baseDir;
      }).toList();
    }
    int newIndex = filteredList.indexOf(currentFile);
    if (newIndex == -1) newIndex = 0;
    if (filteredList.isNotEmpty) {
      _currentPlaylist = filteredList;
      _currentIndex = newIndex;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_currentIndex);
      }
    }
  }

  Future<void> _startServer() async {
    try {
      _streamingServer = LocalStreamingServer(widget.container);
      final port = await _streamingServer!.start().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception('Streaming server timed out'),
      );
      if (mounted) setState(() { _serverPort = port; _serverReady = true; });
    } catch (e) {
      if (mounted) {
        setState(() => _serverError =
            'Could not start media server. Try reopening the file.');
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _streamingServer?.stop();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _setUIVisibility(bool show) {
    if (mounted) {
      setState(() => _showUI = show);
      if (show) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    }
  }

  void _toggleOrientation() {
    setState(() => _isLandscape = !_isLandscape);
    if (_isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  void _toggleShuffle() {
    setState(() {
      final currentFile = _currentPlaylist[_currentIndex];
      if (!_isShuffled) {
        final shuffled = List<String>.from(_currentPlaylist)
          ..remove(currentFile)
          ..shuffle();
        shuffled.insert(0, currentFile);
        _currentPlaylist = shuffled;
        _currentIndex = 0;
        if (_pageController.hasClients) _pageController.jumpToPage(0);
        _isShuffled = true;
      } else {
        _applyFolderFiltering(_selectedFolder, currentFile);
        _isShuffled = false;
      }
    });
  }

  Future<void> _filterByFolder(String folder) async {
    if (folder == 'All' && !_allFilesScanned) {
      if (mounted) setState(() => _isScanningSubfolders = true);
      await _loadRecursiveMedia();
      _allFilesScanned = true;
      if (mounted) setState(() => _isScanningSubfolders = false);
    }
    if (!mounted) return;
    setState(() {
      _selectedFolder = folder;
      final currentFile = _currentPlaylist[_currentIndex];
      _applyFolderFiltering(folder, currentFile);
    });
  }

  Future<void> _openWithApp() async {
    final currentFile = _currentPlaylist[_currentIndex];
    try {
      await vaultExplorerApi.openWithApp(widget.container, currentFile);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to open file in external app: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _deleteCurrentFile() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Delete file?',
            style: TextStyle(color: Colors.white)),
        content: const Text('This action is permanent and cannot be undone.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final currentFile = _currentPlaylist[_currentIndex];
      bool success = false;
      try {
        success =
            await vaultExplorerApi.deleteFile(widget.container, currentFile);
      } catch (e) {
        debugPrint('Error executing API deletion: $e');
      }

      if (success && mounted) {
        setState(() {
          _currentPlaylist.removeAt(_currentIndex);
          _originalList.remove(currentFile);
          if (_currentPlaylist.isEmpty) {
            Navigator.pop(context);
            return;
          }
          if (_currentIndex >= _currentPlaylist.length) {
            _currentIndex = _currentPlaylist.length - 1;
          }
          if (_pageController.hasClients) {
            _pageController.jumpToPage(_currentIndex);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File deleted successfully')));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Failed to delete file'),
            backgroundColor: Colors.red));
      }
    }
  }

  // ── Auto-advance ──────────────────────────────────────────────────────────
  // Called by RealVideoPlayerWidget when the video reaches its end.
  void _onVideoEnd() {
    if (!_autoAdvance) return;
    if (!mounted) return;
    final next = _currentIndex + 1;
    if (next < _currentPlaylist.length) {
      setState(() => _currentIndex = next);
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_serverError != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline,
                  color: Color(0xFFEF5350), size: 40),
              const SizedBox(height: 16),
              Text(_serverError!,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go back',
                    style: TextStyle(color: Color(0xFF4FC3F7))),
              ),
            ]),
          ),
        ),
      );
    }

    if (!_serverReady || _currentPlaylist.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor:
                  AlwaysStoppedAnimation<Color>(Color(0xFF4FC3F7))),
        ),
      );
    }

    final total = _currentPlaylist.length;
    final currentName = _currentPlaylist[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            physics: _pagePhysics,
            itemCount: total,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              final streamUrl =
                  'http://127.0.0.1:$_serverPort/media'
                  '?file=${Uri.encodeQueryComponent(_currentPlaylist[index])}';
              return _MediaPage(
                key: ValueKey(_currentPlaylist[index]),
                fileName: _currentPlaylist[index],
                streamUrl: streamUrl,
                showUI: _showUI,
                onToggleUI: _setUIVisibility,
                skipSeconds: _doubleTapSkipSeconds,
                autoPlay: _autoPlay,
                onVideoEnd: _onVideoEnd,
                onZoomChanged: (allowSwipe) => setState(() {
                  _pagePhysics = allowSwipe
                      ? const ClampingScrollPhysics()
                      : const NeverScrollableScrollPhysics();
                }),
              );
            },
          ),

          // ── Top action bar ──────────────────────────────────────────────
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
              child: Row(children: [
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
                            fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_currentIndex + 1} of $total'
                        '${_isScanningSubfolders ? '  ·  scanning…' : ''}',
                        style: const TextStyle(
                            color: Color(0xFF7A8899), fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.redAccent),
                  tooltip: 'Delete File',
                  onPressed: _deleteCurrentFile,
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  tooltip: 'More Actions',
                  onSelected: (value) {
                    switch (value) {
                      case 'open_with':
                        _openWithApp();
                      case 'toggle_orientation':
                        _toggleOrientation();
                      case 'toggle_shuffle':
                        _toggleShuffle();
                      case 'folder_current':
                        _filterByFolder('Current Folder Only');
                      case 'folder_all':
                        _filterByFolder('All');
                      case 'toggle_autoplay':
                        setState(() => _autoPlay = !_autoPlay);
                      case 'toggle_autoadvance':
                        setState(() => _autoAdvance = !_autoAdvance);
                      default:
                        if (value.startsWith('skip_')) {
                          final seconds = int.parse(value.split('_')[1]);
                          setState(() => _doubleTapSkipSeconds = seconds);
                        }
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem<String>(
                      value: 'open_with',
                      child: Row(children: [
                        Icon(Icons.open_in_new, size: 18),
                        SizedBox(width: 8),
                        Text('Open with App'),
                      ]),
                    ),
                    PopupMenuItem<String>(
                      value: 'toggle_orientation',
                      child: Row(children: [
                        Icon(
                          _isLandscape
                              ? Icons.screen_lock_portrait
                              : Icons.screen_rotation,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(_isLandscape ? 'Portrait Mode' : 'Landscape Mode'),
                      ]),
                    ),
                    PopupMenuItem<String>(
                      value: 'toggle_shuffle',
                      child: Row(children: [
                        Icon(Icons.shuffle,
                            color:
                                _isShuffled ? const Color(0xFF4FC3F7) : Colors.grey,
                            size: 18),
                        const SizedBox(width: 8),
                        Text(_isShuffled
                            ? 'Disable Shuffle'
                            : 'Shuffle Playlist'),
                      ]),
                    ),
                    const PopupMenuDivider(),
                    // ── Folder filter ───────────────────────────────────
                    PopupMenuItem<String>(
                      enabled: false,
                      height: 28,
                      child: Text('Folder Filter',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).disabledColor)),
                    ),
                    PopupMenuItem<String>(
                      value: 'folder_current',
                      child: Row(children: [
                        Icon(Icons.folder_shared,
                            color: _selectedFolder == 'Current Folder Only'
                                ? const Color(0xFF4FC3F7)
                                : Colors.grey,
                            size: 18),
                        const SizedBox(width: 8),
                        const Text('Current Folder Only'),
                      ]),
                    ),
                    PopupMenuItem<String>(
                      value: 'folder_all',
                      child: Row(children: [
                        Icon(Icons.all_inclusive,
                            color: _selectedFolder == 'All'
                                ? const Color(0xFF4FC3F7)
                                : Colors.grey,
                            size: 18),
                        const SizedBox(width: 8),
                        const Text('All (Incl. Subfolders)'),
                      ]),
                    ),
                    const PopupMenuDivider(),
                    // ── Playback ────────────────────────────────────────
                    PopupMenuItem<String>(
                      enabled: false,
                      height: 28,
                      child: Text('Playback',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).disabledColor)),
                    ),
                    PopupMenuItem<String>(
                      value: 'toggle_autoplay',
                      child: Row(children: [
                        Icon(
                          _autoPlay
                              ? Icons.play_circle_outline
                              : Icons.play_circle_filled,
                          color: _autoPlay
                              ? const Color(0xFF4FC3F7)
                              : Colors.grey,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(_autoPlay ? 'Auto-play: On' : 'Auto-play: Off'),
                      ]),
                    ),
                    PopupMenuItem<String>(
                      value: 'toggle_autoadvance',
                      child: Row(children: [
                        Icon(
                          Icons.skip_next,
                          color: _autoAdvance
                              ? const Color(0xFF4FC3F7)
                              : Colors.grey,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(_autoAdvance
                            ? 'Auto-advance: On'
                            : 'Auto-advance: Off'),
                      ]),
                    ),
                    const PopupMenuDivider(),
                    // ── Seek skip ───────────────────────────────────────
                    PopupMenuItem<String>(
                      enabled: false,
                      height: 28,
                      child: Text('Seek Skip',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).disabledColor)),
                    ),
                    ...[5, 10, 15, 30].map((s) => PopupMenuItem<String>(
                          value: 'skip_$s',
                          child: Text(
                              'Skip ${s}s${_doubleTapSkipSeconds == s ? ' ✓' : ''}'),
                        )),
                  ],
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── _MediaPage — routes images vs videos ──────────────────────────────────────

class _MediaPage extends StatefulWidget {
  final String fileName;
  final String streamUrl;
  final bool showUI;
  final ValueChanged<bool> onToggleUI;
  final ValueChanged<bool> onZoomChanged;
  final int skipSeconds;
  final bool autoPlay;
  final VoidCallback onVideoEnd;

  const _MediaPage({
    Key? key,
    required this.fileName,
    required this.streamUrl,
    required this.showUI,
    required this.onToggleUI,
    required this.onZoomChanged,
    required this.skipSeconds,
    required this.autoPlay,
    required this.onVideoEnd,
  }) : super(key: key);

  @override
  State<_MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<_MediaPage> {
  final TransformationController _transformationController =
      TransformationController();
  double _scale = 1.0;
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    final position = _doubleTapDetails?.localPosition;
    setState(() {
      if (_scale == 1.0) {
        _scale = 2.5;
        if (position != null) {
          final x = -position.dx * (_scale - 1);
          final y = -position.dy * (_scale - 1);
          _transformationController.value = Matrix4.identity()
            ..translate(x, y)
            ..scale(_scale);
        } else {
          _transformationController.value = Matrix4.identity()..scale(_scale);
        }
        widget.onZoomChanged(false);
      } else {
        _scale = 1.0;
        _transformationController.value = Matrix4.identity();
        widget.onZoomChanged(true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ext = widget.fileName.split('.').last.toLowerCase();
    final isImg = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);

    return Container(
      color: Colors.black,
      child: isImg
          ? GestureDetector(
              onTap: () => widget.onToggleUI(!widget.showUI),
              onDoubleTapDown: (details) => _doubleTapDetails = details,
              onDoubleTap: _handleDoubleTap,
              child: InteractiveViewer(
                transformationController: _transformationController,
                maxScale: 4.0,
                onInteractionUpdate: (details) {
                  final newScale =
                      _transformationController.value.getMaxScaleOnAxis();
                  if (newScale != _scale) {
                    setState(() => _scale = newScale);
                    widget.onZoomChanged(newScale <= 1.01);
                  }
                },
                onInteractionEnd: (details) {
                  final newScale =
                      _transformationController.value.getMaxScaleOnAxis();
                  if (newScale <= 1.01) widget.onZoomChanged(true);
                },
                child: Center(
                  child: Image.network(
                    widget.streamUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const Center(
                      child: Text('Failed to stream image.',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ),
                ),
              ),
            )
          : RealVideoPlayerWidget(
              streamUrl: widget.streamUrl,
              showUI: widget.showUI,
              onToggleUI: widget.onToggleUI,
              skipSeconds: widget.skipSeconds,
              autoPlay: widget.autoPlay,
              onVideoEnd: widget.onVideoEnd,
              onZoomChanged: widget.onZoomChanged,
            ),
    );
  }
}

// ── RealVideoPlayerWidget ─────────────────────────────────────────────────────

class RealVideoPlayerWidget extends StatefulWidget {
  final String streamUrl;
  final bool showUI;
  final ValueChanged<bool> onToggleUI;
  final int skipSeconds;
  final ValueChanged<bool> onZoomChanged;
  final bool autoPlay;
  final VoidCallback onVideoEnd;

  const RealVideoPlayerWidget({
    Key? key,
    required this.streamUrl,
    required this.showUI,
    required this.onToggleUI,
    required this.skipSeconds,
    required this.onZoomChanged,
    required this.autoPlay,
    required this.onVideoEnd,
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

  bool _showLeftIndicator = false;
  bool _showRightIndicator = false;
  bool _isSpeedHeld = false;

  bool _isMuted = false;
  bool _isLooping = false;
  double _playbackSpeed = 1.0;

  // Track if we've already fired onVideoEnd for this play-through
  bool _endFired = false;

  final TransformationController _videoTransformationController =
      TransformationController();
  double _videoScale = 1.0;
  TapDownDetails? _videoDoubleTapDetails;

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

    _controller.addListener(_onControllerUpdate);

    try {
      await _controller.initialize();
      if (mounted) {
        setState(() {
          _initialized = true;
          _duration = _controller.value.duration;
        });
        await _controller.setVolume(_isMuted ? 0.0 : 1.0);
        await _controller.setLooping(_isLooping);
        await _controller.setPlaybackSpeed(_playbackSpeed);
        // Honour autoPlay preference.
        if (widget.autoPlay) {
          _controller.play();
          _startHideTimer();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _playerError = 'Stream initialization failed: $e');
      }
    }
  }

  void _onControllerUpdate() {
    if (_controller.value.hasError) {
      if (mounted) {
        setState(() => _playerError =
            _controller.value.errorDescription ?? 'ExoPlayer stream error.');
      }
      return;
    }
    if (mounted && _initialized) {
      setState(() {
        _position = _controller.value.position;
        _duration = _controller.value.duration;
        if (!_isDragging && _duration.inMilliseconds > 0) {
          _sliderValue =
              _position.inMilliseconds / _duration.inMilliseconds;
        }
      });
    }

    // Auto-advance: fire once when the video reaches the end (not looping).
    if (_initialized &&
        !_isLooping &&
        _duration > Duration.zero &&
        _position >= _duration &&
        !_endFired) {
      _endFired = true;
      // Small delay so the final frame is visible briefly.
      Future.delayed(const Duration(milliseconds: 400), () {
        widget.onVideoEnd();
      });
    }
    // Reset the sentinel if the user seeks back.
    if (_position < _duration * 0.95) {
      _endFired = false;
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _videoTransformationController.dispose();
    _controller.removeListener(_onControllerUpdate);
    try { _controller.dispose(); } catch (_) {}
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
    if (!widget.showUI) widget.onToggleUI(true);
    _startHideTimer();
  }

  void _onSpeedHoldStart(LongPressStartDetails _) {
    if (!_initialized) return;
    setState(() => _isSpeedHeld = true);
    _controller.setPlaybackSpeed(2.0);
    widget.onToggleUI(false);
    _hideTimer?.cancel();
  }

  void _onSpeedHoldEnd(LongPressEndDetails _) {
    if (!_initialized) return;
    setState(() => _isSpeedHeld = false);
    _controller.setPlaybackSpeed(_playbackSpeed);
    _showControlsAndResetTimer();
  }

  void _toggleMute() {
    _showControlsAndResetTimer();
    setState(() {
      _isMuted = !_isMuted;
      _controller.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  void _toggleLoop() {
    _showControlsAndResetTimer();
    setState(() {
      _isLooping = !_isLooping;
      _controller.setLooping(_isLooping);
      if (_isLooping) _endFired = false; // don't auto-advance when looping
    });
  }

  void _setPlaybackSpeed(double speed) {
    _showControlsAndResetTimer();
    setState(() {
      _playbackSpeed = speed;
      _controller.setPlaybackSpeed(speed);
    });
  }

  void _handleVideoDoubleTap() {
    final position = _videoDoubleTapDetails?.localPosition;
    setState(() {
      if (_videoScale == 1.0) {
        _videoScale = 2.2;
        if (position != null) {
          final x = -position.dx * (_videoScale - 1);
          final y = -position.dy * (_videoScale - 1);
          _videoTransformationController.value = Matrix4.identity()
            ..translate(x, y)
            ..scale(_videoScale);
        } else {
          _videoTransformationController.value =
              Matrix4.identity()..scale(_videoScale);
        }
        widget.onZoomChanged(false);
      } else {
        _videoScale = 1.0;
        _videoTransformationController.value = Matrix4.identity();
        widget.onZoomChanged(true);
      }
    });
  }

  void _skip({required bool backwards}) {
    _showControlsAndResetTimer();
    final currentPos = _controller.value.position;
    final targetPos = backwards
        ? currentPos - Duration(seconds: widget.skipSeconds)
        : currentPos + Duration(seconds: widget.skipSeconds);
    final clampedPos = targetPos < Duration.zero
        ? Duration.zero
        : (targetPos > _duration ? _duration : targetPos);
    _controller.seekTo(clampedPos);
    setState(() {
      if (backwards) {
        _showLeftIndicator = true;
      } else {
        _showRightIndicator = true;
      }
    });
    Timer(const Duration(milliseconds: 550), () {
      if (mounted) {
        setState(() {
          _showLeftIndicator = false;
          _showRightIndicator = false;
        });
      }
    });
  }

  String _formatDuration(Duration duration) {
    final minutes =
        duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds =
        duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (_playerError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline,
                color: Color(0xFFEF5350), size: 36),
            const SizedBox(height: 12),
            Text(_playerError!,
                style: const TextStyle(
                    color: Color(0xFFEF5350), fontSize: 13),
                textAlign: TextAlign.center),
          ]),
        ),
      );
    }

    if (!_initialized) {
      return const Center(
        child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor:
                AlwaysStoppedAnimation<Color>(Color(0xFF4FC3F7))),
      );
    }

    return ClipRect(
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // ── Video canvas ──────────────────────────────────────────────
          InteractiveViewer(
            transformationController: _videoTransformationController,
            maxScale: 6.0,
            minScale: 1.0,
            clipBehavior: Clip.none,
            onInteractionUpdate: (details) {
              final newScale =
                  _videoTransformationController.value.getMaxScaleOnAxis();
              if (newScale != _videoScale) {
                setState(() => _videoScale = newScale);
                widget.onZoomChanged(newScale <= 1.01);
              }
            },
            onInteractionEnd: (details) {
              final newScale =
                  _videoTransformationController.value.getMaxScaleOnAxis();
              if (newScale <= 1.01) widget.onZoomChanged(true);
            },
            child: Center(
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_controller),
                    Row(children: [
                      Expanded(
                        flex: 3,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () {
                            widget.onToggleUI(!widget.showUI);
                            if (!widget.showUI) _startHideTimer();
                          },
                          onDoubleTap: () => _skip(backwards: true),
                          onLongPressStart: _onSpeedHoldStart,
                          onLongPressEnd: _onSpeedHoldEnd,
                          child: Container(),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () {
                            widget.onToggleUI(!widget.showUI);
                            if (!widget.showUI) _startHideTimer();
                          },
                          onDoubleTapDown: (details) =>
                              _videoDoubleTapDetails = details,
                          onDoubleTap: _handleVideoDoubleTap,
                          onLongPressStart: _onSpeedHoldStart,
                          onLongPressEnd: _onSpeedHoldEnd,
                          child: Container(),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () {
                            widget.onToggleUI(!widget.showUI);
                            if (!widget.showUI) _startHideTimer();
                          },
                          onDoubleTap: () => _skip(backwards: false),
                          onLongPressStart: _onSpeedHoldStart,
                          onLongPressEnd: _onSpeedHoldEnd,
                          child: Container(),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),

          // ── Skip indicators ───────────────────────────────────────────
          if (_showLeftIndicator)
            Positioned(
              left: 45,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(30)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.fast_rewind,
                        color: Colors.white, size: 28),
                    const SizedBox(height: 4),
                    Text('-${widget.skipSeconds}s',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),
            ),

          if (_showRightIndicator)
            Positioned(
              right: 45,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(30)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.fast_forward,
                        color: Colors.white, size: 28),
                    const SizedBox(height: 4),
                    Text('+${widget.skipSeconds}s',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),
            ),

          // ── 2× speed indicator ────────────────────────────────────────
          if (_isSpeedHeld)
            Positioned(
              top: 20,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFF4FC3F7).withOpacity(0.6),
                        width: 1),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.fast_forward_rounded,
                        color: Color(0xFF4FC3F7), size: 16),
                    SizedBox(width: 6),
                    Text('2× speed',
                        style: TextStyle(
                            color: Color(0xFF4FC3F7),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3)),
                  ]),
                ),
              ),
            ),

          // ── Bottom controls ───────────────────────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            left: 0,
            right: 0,
            bottom: widget.showUI ? 0 : -140,
            child: Container(
              padding: EdgeInsets.only(
                top: 12,
                bottom: MediaQuery.of(context).padding.bottom + 12,
                left: 16,
                right: 16,
              ),
              color: Colors.black.withOpacity(0.65),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Seek bar
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF4FC3F7),
                      inactiveTrackColor: const Color(0xFF2A3040),
                      thumbColor: const Color(0xFF4FC3F7),
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                      trackShape: const RectangularSliderTrackShape(),
                    ),
                    child: Slider(
                      value: _sliderValue.clamp(0.0, 1.0),
                      onChanged: (value) {
                        _showControlsAndResetTimer();
                        setState(() {
                          _isDragging = true;
                          _sliderValue = value;
                        });
                        final now = DateTime.now();
                        if (now
                                .difference(_lastSeekTime)
                                .inMilliseconds >
                            100) {
                          _lastSeekTime = now;
                          final targetMs =
                              (value * _duration.inMilliseconds).toInt();
                          _controller
                              .seekTo(Duration(milliseconds: targetMs));
                        }
                      },
                      onChangeEnd: (value) {
                        final targetMs =
                            (value * _duration.inMilliseconds).toInt();
                        _controller
                            .seekTo(Duration(milliseconds: targetMs))
                            .then((_) {
                          setState(() => _isDragging = false);
                          _startHideTimer();
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Timestamps
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(_position),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11)),
                      Text(_formatDuration(_duration),
                          style: const TextStyle(
                              color: Color(0xFF7A8899), fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Options row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          _isMuted ? Icons.volume_off : Icons.volume_up,
                          color:
                              _isMuted ? Colors.redAccent : Colors.white,
                          size: 20,
                        ),
                        onPressed: _toggleMute,
                      ),
                      const SizedBox(width: 24),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          Icons.loop,
                          color: _isLooping
                              ? const Color(0xFF4FC3F7)
                              : Colors.white,
                          size: 20,
                        ),
                        onPressed: _toggleLoop,
                      ),
                      const SizedBox(width: 24),
                      // Auto-advance indicator
                      if (_autoAdvance) ...[
                        Icon(Icons.skip_next,
                            color: const Color(0xFF4FC3F7), size: 18),
                        const SizedBox(width: 24),
                      ],
                      // Speed selector
                      Theme(
                        data: Theme.of(context)
                            .copyWith(cardColor: Colors.grey[900]),
                        child: PopupMenuButton<double>(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          initialValue: _playbackSpeed,
                          onSelected: _setPlaybackSpeed,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white24),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${_playbackSpeed}x',
                              style: const TextStyle(
                                  color: Color(0xFF4FC3F7),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          itemBuilder: (context) => [0.5, 1.0, 1.25, 1.5, 2.0]
                              .map((speed) => PopupMenuItem<double>(
                                    value: speed,
                                    height: 36,
                                    child: Text(
                                      '${speed}x',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight:
                                              _playbackSpeed == speed
                                                  ? FontWeight.bold
                                                  : FontWeight.normal),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Centre play/pause ─────────────────────────────────────────
          if (widget.showUI)
            Center(
              child: GestureDetector(
                onTap: () {
                  _showControlsAndResetTimer();
                  setState(() {
                    _controller.value.isPlaying
                        ? _controller.pause()
                        : _controller.play();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                      color: Colors.black45, shape: BoxShape.circle),
                  child: Icon(
                    _controller.value.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow,
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