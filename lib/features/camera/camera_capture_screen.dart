import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'active_recording_registry.dart';
import 'background_video_save.dart';
import 'camera_vault_service.dart';
import 'camera_capture_controls_controller.dart';
import 'camera_capture_lock_controller.dart';
import 'camera_capture_session_controller.dart';
import 'camera_ui_components.dart';
import 'capture_screen_mixin.dart';
import 'camera_media_review_view.dart';
import 'scan/document_quad_overlay.dart';
import 'scan/document_scan_api.dart';
import 'scan/document_scan_editor_screen.dart';
import 'scan/scan_geometry.dart';
import 'vault_camera_controller.dart';

/// What [CameraCaptureScreen] pops with after a successful save.
///
/// Photos are written before the screen closes. Videos are not: they are
/// handed to the file-operation system and keep saving after the screen is
/// gone, so a long recording never holds the user on the capture screen.
/// [backgroundSaves] holds those operations, for the caller to watch.
typedef CameraCaptureResult = ({
  String savedName,
  bool isVideo,
  List<FileOperation> backgroundSaves,
});

class CameraCaptureScreen extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String targetDirPath;

  const CameraCaptureScreen({
    super.key,
    required this.container,
    required this.targetDirPath,
  });

  @override
  ConsumerState<CameraCaptureScreen> createState() =>
      _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends ConsumerState<CameraCaptureScreen>
    with WidgetsBindingObserver, CaptureScreenStateMixin<CameraCaptureScreen> {
  @override
  String get captureControlsKey => _captureControlsKey;

  @override
  String get captureLogTag => 'CameraCaptureScreen';

  @override
  void enterReviewing() {
    _isReviewingMedia = true;
  }

  late CameraVaultService _vaultService;

  late final ActiveRecordingRegistry _activeRecordingRegistry;

  /// Video saves handed to the file-operation system so far. Kept for the
  /// whole life of the screen, not per save attempt: a later attempt that
  /// fails on a photo and is retried must still report the videos that were
  /// already handed off.
  final List<FileOperation> _backgroundSaves = [];
  late final SessionLockController _sessionLockController;
  late final VaultDashboardController _dashboardController;
  bool _autoLockPausedForRecording = false;

  bool _backgroundRecordingActive = false;

  String? _currentRecordingName;

  String? _currentRecordingPath;

  String? _firstSavedCaptureName;

  bool _hasSavedVideoCapture = false;

  bool _isReviewingMedia = false;

  bool _lockedRouteDismissalScheduled = false;

  // --- Document scanning --------------------------------------------------
  final _scanApi = const DocumentScanApi();

  bool _isScanMode = false;

  /// Save scanned pages as one PDF (true) or as separate images (false).
  bool _scanAsPdf = true;

  /// True from the shutter press until the editor opens.
  bool _isProcessingScan = false;

  /// Latest outline from the live detector, in the camera's natural frame.
  final ValueNotifier<ScanQuad?> _liveQuad = ValueNotifier<ScanQuad?>(null);

  Timer? _liveQuadExpiry;

  static const String _captureControlsKey = 'camera_capture';

  @override
  String get captureSessionKey =>
      '${widget.container.uri}\u0000${widget.targetDirPath}';

  @override
  bool get captureIsCountingDown => captureSession.isCountingDown;

  void _onBackgroundRecordingStopRequestedEvent(int volId) {
    if (volId == widget.container.volId && captureIsRecording) {
      unawaited(stopVideoRecording());
    }
  }

  @override
  void initState() {
    super.initState();
    captureFileIoApi = ref.read(vaultFileIoApiProvider);
    captureLifecycleApi = ref.read(vaultLifecycleApiProvider);
    engineEvents = ref.read(vaultEngineEventsProvider);
    _activeRecordingRegistry = ref.read(activeRecordingRegistryProvider);
    _sessionLockController = ref.read(sessionLockControllerProvider);
    _dashboardController = ref.read(vaultDashboardControllerProvider.notifier);
    cameraController = VaultCameraController(engineEvents);

    engineEvents.addBackgroundRecordingStopRequestedListener(
      _onBackgroundRecordingStopRequestedEvent,
    );
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _vaultService = CameraVaultService(
      container: widget.container,
      targetDirPath: widget.targetDirPath,
      fileIoApi: captureFileIoApi,
      lifecycleApi: captureLifecycleApi,
    );
    WidgetsBinding.instance.addObserver(this);

    cameraEventSubscription = cameraController.events.listen(
      handleCameraEvent,
    );
    initCamera();
    startSensorListener();
    unawaited(refreshDisplayRotation());
  }

  @override
  void didChangeMetrics() {
    unawaited(refreshDisplayRotation());
  }

  bool get _isOwnRouteCurrent => ModalRoute.of(context)?.isCurrent ?? false;

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (!_isOwnRouteCurrent) return false;
    if (_isReviewingMedia && capturedMedia.isNotEmpty) {
      return true;
    }
    if (captureIsRecording ||
        isEncrypting ||
        captureIsCountingDown ||
        pendingPhotoCount > 0) {
      return true;
    }
    if (capturedMedia.isNotEmpty) {
      return true;
    }
    return false;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {}

  @override
  void handleCancelBackGesture() {}

  @override
  void handleCommitBackGesture() {
    if (!_isOwnRouteCurrent) return;
    if (_isReviewingMedia && capturedMedia.isNotEmpty) {
      setState(() => _isReviewingMedia = false);
    } else if (capturedMedia.isNotEmpty) {
      HapticFeedback.lightImpact();
      _discardAllMedia();
    }
  }

  @override
  void dispose() {
    _resumeAutoLockAfterRecording();
    engineEvents.removeBackgroundRecordingStopRequestedListener(
      _onBackgroundRecordingStopRequestedEvent,
    );
    WidgetsBinding.instance.removeObserver(this);
    trayScrollController.dispose();
    timer?.cancel();
    exposureHideTimer?.cancel();
    _liveQuadExpiry?.cancel();
    _liveQuad.dispose();
    sensorSubscription?.cancel();
    cameraEventSubscription?.cancel();
    unawaited(cameraController.dispose());

    if (captureIsRecording) {
      unawaited(captureFileIoApi.setKeepScreenOn(false));
    }
    _activeRecordingRegistry.unregister(widget.container.uri);
    if (_backgroundRecordingActive) {
      unawaited(captureFileIoApi.stopBackgroundRecording());
    }

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    lastLifecycleState = state;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      backgroundingFuture = _handleGoingBackground();
    } else if (state == AppLifecycleState.resumed && backgroundingFuture != null) {
      unawaited(_handleResumed());
    }
  }

  void _pauseAutoLockForRecording() {
    if (_autoLockPausedForRecording) return;
    _autoLockPausedForRecording = true;
    _sessionLockController.pauseVaultAutoLock();
    _dashboardController.pauseAutoCloseForActivity(widget.container.volId);
  }

  void _resumeAutoLockAfterRecording() {
    if (!_autoLockPausedForRecording) return;
    _autoLockPausedForRecording = false;
    _dashboardController.resumeAutoCloseAfterActivity(widget.container.volId);
    _sessionLockController.resumeVaultAutoLock();
  }

  Future<void> _handleGoingBackground() async {
    if (captureIsRecording) return;
    await cameraController.close();
    if (mounted) {
      captureSessionController.setUninitialized();
    }
  }

  Future<void> _handleResumed() async {
    final bgFuture = backgroundingFuture;
    backgroundingFuture = null;
    unawaited(refreshDisplayRotation());
    if (bgFuture != null) {
      await bgFuture;
    }
    if (!mounted) return;
    if (_backgroundRecordingActive) {
      unawaited(_resumeFromBackgroundRecording());
    } else if (!cameraController.isInitialized) {
      await initCamera(
        cameraId: selectedCameraId.isNotEmpty ? selectedCameraId : null,
      );
    }
  }

  Future<void> _resumeFromBackgroundRecording() async {}

  @override
  Future<void> initCamera({String? cameraId}) async {
    if (isOpeningCamera) return;
    isOpeningCamera = true;
    try {
      await captureControlsController.loadPersisted();

      final hasPerms = await VaultCameraController.hasPermissions();
      if (!hasPerms) {
        final granted = await cameraController.requestPermissions();
        if (!granted) {
          if (mounted) {
            captureSessionController.setPermissionError(
              context.l10n.cameraPermissionsRequiredMessage,
            );
          }
          return;
        }
      }

      final info = await cameraController.open(
        cameraId: cameraId,
        facing: captureControls.preferredFacing,
        quality: captureControls.videoQuality,
        photoResolution: captureControls.photoResolution,
        scanMode: _isScanMode,
        scanKind: 'document',
      );

      if (!mounted) return;

      if (lastLifecycleState == AppLifecycleState.paused ||
          lastLifecycleState == AppLifecycleState.hidden) {
        await cameraController.close();
        return;
      }

      captureSessionController.setCameraOpened(info);
      await cameraController.setFlash(captureControls.flashMode);
      await cameraController.setZoom(captureCurrentZoom);
    } catch (e) {
      if (mounted) {
        captureSessionController.setPermissionError(
          context.l10n.cameraErrorMessage('$e'),
        );
      }
    } finally {
      isOpeningCamera = false;
    }
  }

  void _onTapToFocus(TapDownDetails details, BoxConstraints constraints) async {
    if (!cameraController.isInitialized) return;

    final natural = cameraDisplayPointToNatural(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
      captureDisplayRotation,
    );
    final nx = natural.x;
    final ny = natural.y;

    setState(() {
      captureFocusPoint = details.localPosition;
    });
    captureSessionController.setShowExposureSlider(true);

    await applyFocusAndExposurePoint(cameraController, nx, ny, logTag: 'CameraCaptureScreen');

    exposureHideTimer?.cancel();
    exposureHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        captureSessionController.setShowExposureSlider(false);
        setState(() {
          captureFocusPoint = null;
        });
        unawaited(cameraController.resetFocusAndExposure());
      }
    });
  }

  @override
  Future<void> setVideoMode(bool videoMode) async {
    if (captureIsRecording ||
        isEncrypting ||
        captureIsCountingDown ||
        isStartingVideo ||
        captureControls.isVideoMode == videoMode) {
      return;
    }

    captureControlsController.setVideoMode(videoMode);
    await applyFlash(cameraController, captureControls.flashMode, logTag: 'CameraCaptureScreen');
  }

  // --- Document scanning --------------------------------------------------

  @override
  bool get supportsDocumentScan => true;

  @override
  bool get captureIsScanMode => _isScanMode;

  @override
  Future<void> setDocumentScanMode(bool enable) async {
    if (enable == _isScanMode ||
        captureIsRecording ||
        isEncrypting ||
        captureIsCountingDown ||
        isStartingVideo) {
      return;
    }
    if (enable && captureControls.isVideoMode) {
      await setVideoMode(false);
      if (captureControls.isVideoMode) return;
    }
    if (!mounted) return;
    setState(() => _isScanMode = enable);
    _liveQuadExpiry?.cancel();
    _liveQuad.value = null;
    await cameraController.setScanMode(enable, kind: 'document');
  }

  @override
  void onDocumentQuadEvent(Map<String, dynamic> event) {
    if (!mounted || !_isScanMode) return;
    final points = event['points'];
    if (event['found'] == true && points is List && points.length == 8) {
      final next = ScanQuad.fromPoints([for (final v in points) (v as num).toDouble()]);
      final previous = _liveQuad.value;
      // Smooth small jitter; jump straight there when the document moved a lot.
      _liveQuad.value = previous != null && previous.maxCornerDistance(next) < 0.08
          ? previous.lerp(next, 0.5)
          : next;
      _liveQuadExpiry?.cancel();
      _liveQuadExpiry = Timer(const Duration(milliseconds: 700), () => _liveQuad.value = null);
    } else {
      _liveQuadExpiry?.cancel();
      _liveQuad.value = null;
    }
  }

  @override
  Future<void> takeScanPage() async {
    if (!cameraController.isInitialized || isEncrypting || isTakingPhoto || _isProcessingScan) {
      return;
    }
    isTakingPhoto = true;
    triggerShutterFlash();
    setState(() => _isProcessingScan = true);

    try {
      final orientationDegrees = await computePreviewRotationDegrees();
      final shot = await cameraController.capturePhoto(
        orientationDegrees: orientationDegrees,
      );
      final jpeg = shot.bytes;
      if (!shot.success || jpeg == null) {
        if (mounted) {
          showErrorToast(shot.error ?? context.l10n.cameraPhotoCaptureFailedMessage);
        }
        return;
      }

      final detection = await _scanApi.detect(jpeg);
      if (!mounted) return;
      setState(() => _isProcessingScan = false);

      final page = await Navigator.push<ScanPage>(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentScanEditorScreen(
            original: jpeg,
            detection: detection,
            api: _scanApi,
            volId: widget.container.volId,
          ),
        ),
      );
      if (page == null || !mounted) return;

      HapticFeedback.lightImpact();
      final isFirstMedia = capturedMedia.isEmpty;
      setState(() {
        capturedMedia.add(
          CapturedMediaItem.scanPage(pageBytes: page.bytes, thumbnailBytes: page.thumbnail),
        );
        if (isFirstMedia) {
          enterReviewing();
        }
      });
      scrollToEndOfTray();
    } catch (_) {
      if (mounted) showErrorToast(context.l10n.scanProcessingFailed);
    } finally {
      isTakingPhoto = false;
      if (mounted) setState(() => _isProcessingScan = false);
    }
  }

  /// Camera preview and document outline cropped to the selected frame ratio.
  Widget _buildScanPreview({required bool isLandscapeFrame}) {
    final sourceAspect = cameraPreviewDisplayAspect(
      previewWidth: cameraController.previewWidth,
      previewHeight: cameraController.previewHeight,
      sensorOrientation: cameraController.sensorOrientation,
      displayRotation: captureDisplayRotation,
    );
    final frameAspect = cameraPreviewFrameAspectRatio(
      isLandscape: isLandscapeFrame,
    );
    return AspectRatio(
      aspectRatio: frameAspect,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraPreviewView(
              textureId: cameraController.textureId!,
              previewWidth: cameraController.previewWidth,
              previewHeight: cameraController.previewHeight,
              sensorOrientation: cameraController.sensorOrientation,
              displayRotation: captureDisplayRotation,
              frameAspectRatio: frameAspect,
              showShutterFlash: captureShowShutterFlash,
            ),
            // The front camera's preview is mirrored, so the outline would be too.
            if (captureControls.preferredFacing != 'front')
              IgnorePointer(
                child: DocumentQuadOverlay(
                  quad: _liveQuad,
                  displayRotation: captureDisplayRotation,
                  sourceAspectRatio: sourceAspect,
                  frameAspectRatio: frameAspect,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanStatusBar() {
    final l10n = context.l10n;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ValueListenableBuilder<ScanQuad?>(
          valueListenable: _liveQuad,
          builder: (context, quad, _) => _ScanPill(
            text: quad == null ? l10n.scanHintSearching : l10n.scanHintFound,
            highlight: quad != null,
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _scanAsPdf = !_scanAsPdf);
          },
          child: _ScanPill(
            text: _scanAsPdf ? l10n.scanOutputPdf : l10n.scanOutputImages,
            icon: _scanAsPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
          ),
        ),
      ],
    );
  }

  /// Saves [pages] as one PDF. Returns its file name, or null on failure.
  Future<({String? name, bool insufficientSpace})> _saveScansAsPdf(
    List<CapturedMediaItem> pages,
  ) async {
    String? virtualPath;
    try {
      final pdf = await _scanApi.buildPdf([for (final p in pages) p.fullPhotoBytes!]);
      if (!await _vaultService.hasEnoughSpaceFor(pdf.length)) {
        return (name: null, insufficientSpace: true);
      }
      final name = await _vaultService.nextAvailableScanPdfName();
      virtualPath = _vaultService.buildVirtualPath(name);
      final ok = widget.container.isLocalStorage
          ? await captureFileIoApi.writeWholeFile(
              widget.container,
              virtualPath,
              pdf,
            )
          : await cameraController.savePhotoToVault(
              bytes: pdf,
              volId: widget.container.volId,
              virtualPath: virtualPath,
            );
      if (!ok || !await _vaultService.finalizeVaultWrite(virtualPath)) {
        await _vaultService.deleteFile(virtualPath);
        return (name: null, insufficientSpace: false);
      }
      return (name: name, insufficientSpace: false);
    } catch (_) {
      if (virtualPath != null) await _vaultService.deleteFile(virtualPath);
      return (name: null, insufficientSpace: false);
    }
  }

  void _removeAlreadySavedMedia(
    CapturedMediaItem item,
    List<CapturedMediaItem> mediaToSave,
  ) {
    mediaToSave.remove(item);
    capturedMedia.remove(item);
  }

  void _handleSaveFailure(
    List<CapturedMediaItem> mediaToSave,
    List<CapturedMediaItem> successfullySaved,
    String message,
  ) {
    for (final item in successfullySaved) {
      _removeAlreadySavedMedia(item, mediaToSave);
    }
    if (mounted) {
      setState(() {});
      showErrorToast(message);
    }
  }

  /// Hands one recorded video to the file-operation system and returns the
  /// operation. The save (trim, write into the vault, wipe of the plaintext
  /// copy) runs in the background, so the caller can leave this screen at once
  /// and the progress shows in the usual transfer UI.
  FileOperation _enqueueBackgroundVideoSave({
    required FileOperationService opSvc,
    required CapturedMediaItem item,
    required String name,
    required String virtualPath,
    required int estimatedBytes,
  }) {
    final job = BackgroundVideoSave(
      container: widget.container,
      vaultService: _vaultService,
      fileIoApi: captureFileIoApi,
      videoPath: item.videoPath!,
      virtualPath: virtualPath,
      trimStartMs: item.trimStartMs,
      trimEndMs: item.trimEndMs,
      durationMs: item.videoDurationMs,
      failureMessage: context.l10n.statusFailed,
    );

    // Leaving this screen must not let the vault lock itself out from under
    // the write, so hold both auto-lock timers until the operation ends.
    // Both holds are counted, so they stack with the screen's own.
    final sessionLock = _sessionLockController;
    final dashboard = _dashboardController;
    final volId = widget.container.volId;
    sessionLock.pauseVaultAutoLock();
    dashboard.pauseAutoCloseForActivity(volId);

    final op = opSvc.enqueueImport(
      dest: widget.container,
      destDirPath: widget.targetDirPath,
      items: [
        ClipboardItem(path: name, isDir: false, sizeBytes: estimatedBytes),
      ],
      isFolder: false,
      performImport: job.run,
      l10n: context.l10n,
    );

    void releaseOnFinish() {
      final finished =
          op.status != FileOperationStatus.pending &&
          op.status != FileOperationStatus.running;
      if (!finished) return;
      op.removeListener(releaseOnFinish);
      dashboard.resumeAutoCloseAfterActivity(volId);
      sessionLock.resumeVaultAutoLock();
    }

    op.addListener(releaseOnFinish);
    return op;
  }

  Future<void> _commitAllMediaToVault(List<CapturedMediaItem> mediaToSave) async {
    if (mediaToSave.isEmpty) return;

    captureSessionController.setEncrypting(
      true,
      label: widget.container.isLocalStorage
          ? context.l10n.savingLabel
          : context.l10n.savingToVault,
    );
    await Future.delayed(const Duration(milliseconds: 50));

    final successfullySaved = <CapturedMediaItem>[];
    // Videos are written after this screen is gone, so their names are not in
    // the folder yet. Keep them out of the pool for the next name.
    final opSvc = ref.read(fileOperationServiceProvider);
    final reservedNames = <String>{
      for (final e in opSvc.getActivePlaceholders(
        widget.container.volId,
        widget.targetDirPath,
      ))
        e.name,
    };
    try {
      String? firstName;
      bool hasVideo = false;

      // Scanned pages become one PDF when that output is selected; everything
      // else is saved individually as before.
      final scanPages = [
        for (final m in mediaToSave)
          if (m.isScan && m.isPhoto && m.fullPhotoBytes != null) m,
      ];
      final bundleScansAsPdf = _scanAsPdf && scanPages.isNotEmpty;
      if (bundleScansAsPdf) {
        final pdfResult = await _saveScansAsPdf(scanPages);
        if (pdfResult.name == null) {
          // Keep everything on screen so nothing is lost; the user can retry or
          // switch to saving images.
          if (mounted) {
            _handleSaveFailure(
              mediaToSave,
              successfullySaved,
              pdfResult.insufficientSpace
                  ? context.l10n.cameraNotEnoughVaultSpaceMessage
                  : context.l10n.scanPdfFailed,
            );
          }
          return;
        }
        firstName = pdfResult.name!;
        _firstSavedCaptureName ??= pdfResult.name;
        successfullySaved.addAll(scanPages);
      }

      for (final item in List<CapturedMediaItem>.from(mediaToSave)) {
        if (item.isPhoto && item.fullPhotoBytes != null) {
          if (bundleScansAsPdf && item.isScan) continue;
          final bytes = item.fullPhotoBytes!;
          if (!await _vaultService.hasEnoughSpaceFor(bytes.length)) {
            if (mounted) {
              _handleSaveFailure(
                mediaToSave,
                successfullySaved,
                context.l10n.cameraNotEnoughVaultSpaceMessage,
              );
            }
            return;
          }
          final name = item.isScan
              ? await _vaultService.nextAvailableScanImageName()
              : await _vaultService.nextAvailableName(isPhoto: true);
          final virtualPath = _vaultService.buildVirtualPath(name);
          final ok = widget.container.isLocalStorage
              ? await captureFileIoApi.writeWholeFile(
                  widget.container,
                  virtualPath,
                  bytes,
                )
              : await cameraController.savePhotoToVault(
                  bytes: bytes,
                  volId: widget.container.volId,
                  virtualPath: virtualPath,
                );
          if (!ok || !await _vaultService.finalizeVaultWrite(virtualPath)) {
            await _vaultService.deleteFile(virtualPath);
            if (mounted) {
              _handleSaveFailure(
                mediaToSave,
                successfullySaved,
                context.l10n.cameraCouldNotSaveCaptureMessage,
              );
            }
            return;
          }
          firstName ??= name;
          _firstSavedCaptureName ??= name;
          successfullySaved.add(item);
        } else if (item.isVideo && item.videoPath != null) {
          // Check space while the capture is still on screen, so a full vault
          // is reported with the video intact and retryable. Anything that
          // goes wrong after the hand-off below can only be reported in the
          // transfer UI.
          final sourceBytes = await _vaultService.localFileSize(
            item.videoPath!,
          );
          final estimatedBytes = sourceBytes == null
              ? 0
              : BackgroundVideoSave.estimateBytes(
                  sourceBytes: sourceBytes,
                  trimStartMs: item.trimStartMs,
                  trimEndMs: item.trimEndMs,
                  durationMs: item.videoDurationMs,
                );
          if (estimatedBytes > 0 &&
              !await _vaultService.hasEnoughSpaceFor(estimatedBytes)) {
            if (mounted) {
              _handleSaveFailure(
                mediaToSave,
                successfullySaved,
                context.l10n.cameraNotEnoughVaultSpaceMessage,
              );
            }
            return;
          }
          final name = await _vaultService.nextAvailableName(
            isPhoto: false,
            reserved: reservedNames,
          );
          reservedNames.add(name);
          final virtualPath = _vaultService.buildVirtualPath(name);
          _backgroundSaves.add(
            _enqueueBackgroundVideoSave(
              opSvc: opSvc,
              item: item,
              name: name,
              virtualPath: virtualPath,
              estimatedBytes: estimatedBytes,
            ),
          );
          firstName ??= name;
          hasVideo = true;
          _firstSavedCaptureName ??= name;
          _hasSavedVideoCapture = true;
          // From here on the operation owns the recording, so it must leave
          // the tray: a later failure in this loop must not offer it again.
          successfullySaved.add(item);
        }
      }

      if (mounted) {
        Navigator.pop(
          context,
          (
            savedName: _firstSavedCaptureName ?? firstName ?? 'media',
            isVideo: _hasSavedVideoCapture || hasVideo,
            backgroundSaves: List.unmodifiable(_backgroundSaves),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        _handleSaveFailure(
          mediaToSave,
          successfullySaved,
          context.l10n.cameraCouldNotSaveCaptureMessage,
        );
      }
    } finally {
      if (mounted) captureSessionController.setEncrypting(false);
    }
  }

  @override
  Future<void> startVideoRecording() async {
    if (!cameraController.isInitialized ||
        isEncrypting ||
        captureIsRecording ||
        isStartingVideo) {
      return;
    }

    captureSessionController.setStartingVideo(true);

    try {
      final name = await _vaultService.nextAvailableName(isPhoto: false);
      final virtualPath = _vaultService.buildVirtualPath(name);

      _currentRecordingName = name;
      _currentRecordingPath = virtualPath;

      await cameraController.setOrientationDegrees(
        await computePreviewRotationDegrees(),
      );

      final result = await cameraController.startVideoRecording(
        volId: widget.container.volId,
        virtualPath: virtualPath,
      );

      if (!result.success) {
        showErrorToast(
          result.error ?? context.l10n.cameraRecordingFailedMessage,
        );
        return;
      }

      recordingStart = DateTime.now();
      setState(() => captureIsRecording = true);
      _pauseAutoLockForRecording();

      if (!mounted) return;
      captureSessionController.startRecording();
      unawaited(captureFileIoApi.setKeepScreenOn(true));
      _activeRecordingRegistry.register(
        widget.container.uri,
        stopVideoRecording,
      );

      _backgroundRecordingActive = true;
      unawaited(
        captureFileIoApi.startBackgroundRecording(
          volId: widget.container.volId,
          containerName: widget.container.displayName,
        ),
      );

      timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted || recordingStart == null) return;
        final elapsed = DateTime.now().difference(recordingStart!).inSeconds;
        captureSessionController.updateTimerText(
          '${(elapsed ~/ 60).toString().padLeft(2, '0')}:${(elapsed % 60).toString().padLeft(2, '0')}',
        );
      });
    } catch (e) {
      showErrorToast(
        context.l10n.cameraRecordingFailedWithReasonMessage('$e'),
      );
    } finally {
      captureSessionController.setStartingVideo(false);
      if (pendingStopAfterStart) {
        pendingStopAfterStart = false;
        if (captureIsRecording) stopVideoRecording();
      }
    }
  }

  @override
  Future<void> stopVideoRecording() async {
    if (!cameraController.isInitialized || !captureIsRecording) return;

    timer?.cancel();
    final startedAt = recordingStart;
    recordingStart = null;
    setState(() => captureIsRecording = false);
    _resumeAutoLockAfterRecording();

    try {
      final isFirstMedia = capturedMedia.isEmpty;
      final result = await cameraController.stopVideoRecordingForReview();

      final elapsedMs = startedAt == null
          ? 9999
          : DateTime.now().difference(startedAt).inMilliseconds;
      if (elapsedMs < 500 || !result.success || result.videoPath == null) {
        if (result.videoPath != null) {
          await cameraController.discardVideo(result.videoPath!);
        }
        if (mounted) {
          showErrorToast(context.l10n.cameraRecordingTooShortMessage);
        }
        return;
      }

      setState(() {
        capturedMedia.add(
          CapturedMediaItem.video(
            videoPath: result.videoPath!,
            videoDurationMs: result.durationMs,
            thumbnailBytes: result.thumbnail ?? Uint8List(0),
          ),
        );
        if (isFirstMedia) {
          _isReviewingMedia = true;
        }
      });
    } catch (e) {
      if (mounted) {
        showErrorToast(
          context.l10n.cameraCouldNotSaveRecordingWithReasonMessage('$e'),
        );
      }
    } finally {
      unawaited(captureFileIoApi.setKeepScreenOn(false));
      _activeRecordingRegistry.unregister(widget.container.uri);
      if (_backgroundRecordingActive) {
        _backgroundRecordingActive = false;
        unawaited(captureFileIoApi.stopBackgroundRecording());
      }
    }
  }

  void _discardAllMedia() {
    for (final item in capturedMedia) {
      if (item.isVideo && item.videoPath != null) {
        cameraController.discardVideo(item.videoPath!);
      }
    }
    setState(() {
      capturedMedia.clear();
      _isReviewingMedia = false;
    });
  }

  void _dismissRouteAfterContainerLock() {
    if (_lockedRouteDismissalScheduled) return;
    _lockedRouteDismissalScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) return;
      final navigator = Navigator.of(context);
      navigator.popUntil((candidate) => candidate == route);
      if (route.isActive) navigator.removeRoute(route);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    ref.watch(cameraCaptureControlsProvider(_captureControlsKey));
    ref.watch(cameraCaptureSessionProvider(captureSessionKey));
    final lockProvider = cameraCaptureLockProvider(widget.container.volId);
    ref.listen<bool>(lockProvider, (previous, locked) {
      if (locked && previous != true) {
        _dismissRouteAfterContainerLock();
      }
    });
    final isContainerLocked = ref.watch(lockProvider);
    if (isContainerLocked) {
      _dismissRouteAfterContainerLock();
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }
    if (_isReviewingMedia && capturedMedia.isNotEmpty) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          setState(() => _isReviewingMedia = false);
        },
        child: CameraMediaReviewView(
          initialMedia: capturedMedia,
          iconTurns: captureIconTurns,
          onMediaChanged: (updated) {
            setState(() {
              capturedMedia
                ..clear()
                ..addAll(updated);
            });
          },
          onDiscard: _discardAllMedia,
          onTakeMoreMedia: () {
            setState(() => _isReviewingMedia = false);
          },
          onSaveMedia: _commitAllMediaToVault,
        ),
      );
    }

    return PopScope(
      canPop: !captureIsRecording && !isEncrypting && !captureIsCountingDown && capturedMedia.isEmpty && pendingPhotoCount == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (capturedMedia.isNotEmpty) {
          HapticFeedback.lightImpact();
          _discardAllMedia();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (isInitialized && cameraController.textureId != null)
              LayoutBuilder(
                builder: (context, constraints) {
                  final bool isLandscapeFrame =
                      constraints.maxWidth > constraints.maxHeight;

                  return GestureDetector(
                    onScaleStart: (_) => baseZoom = captureCurrentZoom,
                    onScaleUpdate: (d) async {
                      double target = (baseZoom * d.scale).clamp(
                        captureMinZoom,
                        captureMaxZoom,
                      );
                      if (target != captureCurrentZoom) {
                        captureSessionController.setZoom(target);
                        await applyZoomSilent(cameraController, target);
                      }
                    },
                    onTapDown: (details) => _onTapToFocus(details, constraints),
                    child: Center(
                      child: _isScanMode
                          ? _buildScanPreview(
                              isLandscapeFrame: isLandscapeFrame,
                            )
                          : CameraPreviewView(
                              textureId: cameraController.textureId!,
                              previewWidth: cameraController.previewWidth,
                              previewHeight: cameraController.previewHeight,
                              sensorOrientation: cameraController.sensorOrientation,
                              displayRotation: captureDisplayRotation,
                              frameAspectRatio: cameraPreviewFrameAspectRatio(
                                isLandscape: isLandscapeFrame,
                              ),
                              showShutterFlash: captureShowShutterFlash,
                            ),
                    ),
                  );
                },
              )
            else if (permissionError != null)
              Center(
                child: Text(
                  permissionError!,
                  style: const TextStyle(color: Colors.white),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            CameraFocusExposureOverlay(
              focusPoint: captureFocusPoint,
              showExposureSlider: captureShowExposureSlider,
              currentExposureEv: captureCurrentExposureEv,
              minExposureEv: captureMinExposureEv,
              maxExposureEv: captureMaxExposureEv,
              onExposureChanged: (val) async {
                captureSessionController.setExposureEv(val);
                await applyExposureOffsetSilent(cameraController, val);
              },
            ),

            if (_isScanMode && isInitialized)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 72,
                left: 0,
                right: 0,
                child: _buildScanStatusBar(),
              ),

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: CameraTopControlsBar(
                isVideoMode: captureControls.isVideoMode,
                isRecording: captureIsRecording,
                isCountingDown: captureIsCountingDown,
                timerText: captureTimerText,
                videoQuality: captureControls.videoQuality,
                photoResolution: captureControls.photoResolution,
                photoResolutions: captureSession.photoResolutions,
                videoQualities: captureSession.videoQualities,
                currentPhotoResolution: captureSession.currentPhotoResolution,
                currentVideoResolution: captureSession.currentVideoResolution,
                selectedAspectRatio: captureControls.aspectRatio,
                onAspectRatioChanged: captureControlsController.selectAspectRatio,
                timerDelaySeconds: captureControls.timerDelaySeconds,
                flashMode: captureControls.flashMode,
                hasFlash: captureHasFlash,
                iconTurns: captureIconTurns,
                onClose: () => Navigator.pop(context),
                onVideoQualityChanged: changeQuality,
                onPhotoResolutionChanged: changePhotoResolution,
                onCycleTimerDelay: captureControlsController.cycleTimerDelay,
                onCycleFlashMode: () {
                  final nextMode = captureControlsController.cyclePhotoFlashMode();
                  unawaited(applyFlash(cameraController, nextMode, logTag: 'CameraCaptureScreen'));
                },
                onPhotoTorchActivated: () {
                  final mode = captureControlsController.activatePhotoTorch();
                  if (mode != null) {
                    unawaited(applyFlash(cameraController, mode, logTag: 'CameraCaptureScreen'));
                  }
                },
              ),
            ),

            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: buildBottomControls(),
            ),

            if (isLandscape && (capturedMedia.isNotEmpty || pendingPhotoCount > 0) && !captureIsRecording && !captureIsCountingDown)
              Positioned(
                left: 16.0 + MediaQuery.paddingOf(context).left,
                bottom: 76.0 + MediaQuery.paddingOf(context).bottom,
                child: buildCapturedMediaTray(),
              ),

            if (captureIsCountingDown)
              Center(
                child: buildRotatedWidget(
                  iconTurns: captureIconTurns,
                  child: Text(
                    '$countdownValue',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 120,
                      shadows: [Shadow(blurRadius: 20)],
                    ),
                  ),
                ),
              ),

            if (_isProcessingScan)
              Container(
                color: Colors.black45,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      Text(
                        context.l10n.scanDetectingEdges,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (isEncrypting)
              Container(
                color: Colors.black54,
                child: Center(
                  child: buildRotatedWidget(
                    iconTurns: captureIconTurns,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 20),
                        Text(
                          busyLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small rounded label used on the scan overlay.
class _ScanPill extends StatelessWidget {
  const _ScanPill({required this.text, this.icon, this.highlight = false});

  final String text;
  final IconData? icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: highlight ? Colors.amber : Colors.black54,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: highlight ? Colors.amber : Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              color: highlight ? Colors.black : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
