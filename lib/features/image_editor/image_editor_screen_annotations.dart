part of 'image_editor_screen.dart';

/// Tool selection, tool colours, text and redaction annotations and the crop
/// aspect.
///
/// Moved out of [_ImageEditorScreenState] as is: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _ImageEditorAnnotations on _ImageEditorScreenState {
  Future<void> _selectTool(EditorTool tool) async {
    if (_document.isSaving) return;
    if (tool == EditorTool.crop ||
        tool == EditorTool.text ||
        tool == EditorTool.redact ||
        _controls.activeTool == EditorTool.crop ||
        _controls.activeTool == EditorTool.text ||
        _controls.activeTool == EditorTool.redact) {
      _resetZoom(animate: false);
    }
    if (tool == EditorTool.crop) {
      _cropEntryImage?.dispose();
      _cropEntryImage = _workingImage?.clone();
      _controlsController.setCropRotationAngle(0.0);
      _cropFlippedHorizontal = false;
    }
    if (tool == EditorTool.text) {
      _textShelfTab = _TextShelfTab.style;
      _editingTextAnnotationIndex = null;
      _textEntrySnapshot = null;
      _activeTextNotifier = ValueNotifier(
        TextMarkAnnotation(
          position: const Offset(0.5, 0.5),
          text: context.l10n.imageEditorTextPlaceholder,
          color: Colors.white,
          fontSizeFraction: 0.045,
          rotation: 0.0,
          opacity: 1.0,
          styleId: 'L2',
        ),
      );
    }
    if (tool == EditorTool.draw) {
      _drawShelfTab = _DrawShelfTab.color;
      _drawSessionSnapshot = _annotations
          .whereType<DrawingAnnotation>()
          .toList();
    }
    if (tool == EditorTool.redact) {
      _selectedRedactIndex = null;
      _isAddingRedact = true;
      _redactSessionSnapshot = _annotations
          .whereType<RedactAnnotation>()
          .toList();
    }
    if (tool == EditorTool.tuneImage) {
      _resetTuneValues();
    }
    _controlsController.toggleTool(tool);
  }

  void _clearDrawAnnotations() {
    _pushUndoSnapshot();
    final nonDraw = _annotations.where((a) => a is! DrawingAnnotation).toList();
    _annotationsController.setAll(nonDraw);
    _documentController.markEdited();
  }

  void _deleteActiveText() {
    _pushUndoSnapshot();
    _activeTextNotifier?.dispose();
    _activeTextNotifier = null;
    _textEntrySnapshot = null;
    _editingTextAnnotationIndex = null;
    _controlsController.clearActiveTool();
    _documentController.markEdited();
  }

  void _setToolColor(Color color) {
    if (_controls.activeTool == EditorTool.redact) {
      _controlsController.setRedactColor(color);
      final idx = _selectedRedactIndex;
      if (idx != null && idx >= 0 && idx < _annotations.length) {
        final current = _annotations[idx];
        if (current is RedactAnnotation && current.color != color) {
          if (_isRedactColorWheelInteracting) {
            if (!_hasRedactColorWheelSnapshot) {
              _pushUndoSnapshot();
              _hasRedactColorWheelSnapshot = true;
            }
          } else {
            _pushUndoSnapshot();
          }
          _annotationsController.update(idx, current.copyWith(color: color));
        }
      }
    } else {
      _controlsController.setColor(color);
    }
  }

  void _onRedactColorWheelInteraction(bool interacting) {
    _isRedactColorWheelInteracting = interacting;
    _hasRedactColorWheelSnapshot = false;
  }

  void _addAnnotation(EditAnnotation annotation) {
    _pushUndoSnapshot();
    _annotationsController.add(annotation);
  }

  Future<void> _handleTextTapped(Offset normalizedPosition) async {
    final l10n = context.l10n;
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _TextAnnotationDialog(
        title: l10n.addTextAnnotationTitle,
        hintText: l10n.addTextAnnotationHint,
        cancelLabel: l10n.cancel,
        addLabel: l10n.add,
      ),
    );

    final trimmed = text?.trim();
    if (trimmed == null || trimmed.isEmpty) return;

    _addAnnotation(
      TextMarkAnnotation(
        position: normalizedPosition,
        text: trimmed,
        color: _controls.currentColor,
        fontSizeFraction: _controls.currentFontSizeFraction,
      ),
    );
  }

  Future<void> _showTextEditDialog() async {
    final notifier = _activeTextNotifier;
    if (notifier == null) return;
    final current = notifier.value.text;
    final initialVal = current == context.l10n.imageEditorTextPlaceholder
        ? ''
        : current;
    final l10n = context.l10n;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _TextAnnotationDialog(
        title: l10n.addTextAnnotationTitle,
        hintText: l10n.addTextAnnotationHint,
        cancelLabel: l10n.cancel,
        addLabel: l10n.add,
        initialText: initialVal,
        showDelete:
            _editingTextAnnotationIndex != null ||
            (initialVal.isNotEmpty &&
                _annotations.any((a) => a is TextMarkAnnotation)),
        onDelete: () {
          Navigator.of(dialogContext).pop('__DELETE__');
        },
      ),
    );

    if (result == '__DELETE__') {
      _deleteActiveText();
      return;
    }

    final trimmed = result?.trim();
    if (trimmed != null && trimmed.isNotEmpty && _activeTextNotifier != null) {
      _activeTextNotifier!.value = _activeTextNotifier!.value.copyWith(
        text: trimmed,
      );
    }
  }

  void _setCropAspect(double? ratio) {
    _controlsController.setCropAspectRatio(ratio);
    final notifier = _cropRectNotifier;
    final boxSize = _cropBoxSize;
    if (notifier == null || boxSize == null) return;
    final angleRad = _controls.cropRotationAngle * math.pi / 180.0;
    notifier.value = _calculateMaxInscribedRect(boxSize, angleRad, ratio);
  }
}
