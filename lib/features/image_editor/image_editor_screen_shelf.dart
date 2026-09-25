part of 'image_editor_screen.dart';

// Extracted from _ImageEditorScreenState's layout/shelf/tool-selector
// _buildXxx methods -- pure presentation (data + callbacks in, Widget out),
// no state of their own. _buildBody stays on the State itself: it mutates
// _cropBoxSize/_cropRectNotifier mid-build, which isn't safe to pull out
// without changing that lifecycle.

/// Portrait layout: image body, then (if no error) the contextual shelf and
/// the tool-selector row underneath it. Extracted from
/// `_ImageEditorScreenState._buildPortraitLayout`.
class _PortraitLayout extends StatelessWidget {
  const _PortraitLayout({
    required this.body,
    required this.hasError,
    required this.shelf,
    required this.toolSelectorRow,
  });

  final Widget body;
  final bool hasError;
  final Widget shelf;
  final Widget toolSelectorRow;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: body),
        if (!hasError) ...[shelf, toolSelectorRow],
      ],
    );
  }
}

/// Landscape layout: image body on the left, a fixed-width right-side
/// control cockpit (contextual shelf + squared tool grid) on the right.
/// Extracted from `_ImageEditorScreenState._buildLandscapeLayout`.
class _LandscapeLayout extends StatelessWidget {
  const _LandscapeLayout({
    required this.body,
    required this.hasError,
    required this.shelf,
    required this.squaredToolGrid,
  });

  final Widget body;
  final bool hasError;
  final Widget shelf;
  final Widget squaredToolGrid;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: body),
        if (!hasError)
          Container(
            width: 290,
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border(
                left: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
            ),
            child: SafeArea(
              left: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(child: shelf),
                    ),
                    const Divider(color: Colors.white12, height: 16),
                    squaredToolGrid,
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Portrait bottom tool-selector row (crop/draw/text/redact). Extracted
/// from `_ImageEditorScreenState._buildToolSelectorRow`.
class _ToolSelectorRow extends StatelessWidget {
  const _ToolSelectorRow({
    required this.l10n,
    required this.activeTool,
    required this.onSelectTool,
  });

  final AppLocalizations l10n;
  final EditorTool activeTool;
  final void Function(EditorTool) onSelectTool;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ToolButton(
            icon: Icons.crop_rounded,
            label: l10n.cropToolLabel,
            selected: activeTool == EditorTool.crop,
            onTap: () => onSelectTool(EditorTool.crop),
          ),
          _ToolButton(
            icon: Icons.brush_rounded,
            label: l10n.drawToolLabel,
            selected: activeTool == EditorTool.draw,
            onTap: () => onSelectTool(EditorTool.draw),
          ),
          _ToolButton(
            icon: Icons.text_fields_rounded,
            label: l10n.textToolLabel,
            selected: activeTool == EditorTool.text,
            onTap: () => onSelectTool(EditorTool.text),
          ),
          _ToolButton(
            icon: Icons.visibility_off_outlined,
            label: l10n.redactToolLabel,
            selected: activeTool == EditorTool.redact,
            onTap: () => onSelectTool(EditorTool.redact),
          ),
        ],
      ),
    );
  }
}

/// Landscape squared 2x2 tool grid. Extracted from
/// `_ImageEditorScreenState._buildSquaredToolGrid`.
class _SquaredToolGrid extends StatelessWidget {
  const _SquaredToolGrid({
    required this.l10n,
    required this.activeTool,
    required this.onSelectTool,
  });

  final AppLocalizations l10n;
  final EditorTool activeTool;
  final void Function(EditorTool) onSelectTool;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: _SquareToolCard(
                icon: Icons.crop_rounded,
                label: l10n.cropToolLabel,
                selected: activeTool == EditorTool.crop,
                onTap: () => onSelectTool(EditorTool.crop),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SquareToolCard(
                icon: Icons.brush_rounded,
                label: l10n.drawToolLabel,
                selected: activeTool == EditorTool.draw,
                onTap: () => onSelectTool(EditorTool.draw),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _SquareToolCard(
                icon: Icons.text_fields_rounded,
                label: l10n.textToolLabel,
                selected: activeTool == EditorTool.text,
                onTap: () => onSelectTool(EditorTool.text),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SquareToolCard(
                icon: Icons.visibility_off_outlined,
                label: l10n.redactToolLabel,
                selected: activeTool == EditorTool.redact,
                onTap: () => onSelectTool(EditorTool.redact),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The tool-dependent contextual shelf above the tool selector: crop
/// controls (angle dial + aspect chips), or draw/redact/text controls
/// (color swatches + the relevant action buttons). Extracted from
/// `_ImageEditorScreenState._buildContextualShelf` -- pure data+callback
/// composition, no mutation, just a lot of inputs because it renders
/// differently per active tool.
class _ContextualShelf extends StatelessWidget {
  const _ContextualShelf({
    required this.l10n,
    required this.isLandscape,
    required this.activeTool,
    required this.cropRotationAngle,
    required this.cropAspectRatio,
    required this.cropBoxSize,
    required this.onRotateAngleChanged,
    required this.onResetRotation,
    required this.onRotate90,
    required this.onSetCropAspect,
    required this.currentColor,
    required this.onSetColor,
    required this.onShowStrokeWidthPicker,
    required this.hasAnnotations,
    required this.onClearAllAnnotations,
    required this.onShowFontSizePicker,
  });

  final AppLocalizations l10n;
  final bool isLandscape;
  final EditorTool activeTool;
  final double cropRotationAngle;
  final double? cropAspectRatio;
  final Size? cropBoxSize;
  final ValueChanged<double> onRotateAngleChanged;
  final VoidCallback onResetRotation;
  final VoidCallback onRotate90;
  final ValueChanged<double?> onSetCropAspect;
  final Color currentColor;
  final ValueChanged<Color> onSetColor;
  final VoidCallback onShowStrokeWidthPicker;
  final bool hasAnnotations;
  final VoidCallback onClearAllAnnotations;
  final VoidCallback onShowFontSizePicker;

  @override
  Widget build(BuildContext context) {
    switch (activeTool) {
      case EditorTool.crop:
        final currentAspect = cropBoxSize == null
            ? 1.0
            : cropBoxSize!.width / cropBoxSize!.height;

        final aspectOptions = [
          (label: l10n.cropAspectFreeLabel, ratio: null),
          (label: l10n.cropAspectSquareLabel, ratio: 1.0),
          (label: l10n.cropAspectOriginalLabel, ratio: currentAspect),
          (label: '4:3', ratio: 4 / 3),
          (label: '16:9', ratio: 16 / 9),
        ];

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: _AngleRulerDial(
                angle: cropRotationAngle,
                onAngleChanged: onRotateAngleChanged,
                onReset: onResetRotation,
                onRotate90: onRotate90,
              ),
            ),
            const SizedBox(height: 6),
            if (isLandscape)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  for (final opt in aspectOptions)
                    _AspectChip(
                      label: opt.label,
                      selected: opt.ratio == null
                          ? cropAspectRatio == null
                          : (cropAspectRatio != null &&
                              (cropAspectRatio! - opt.ratio!).abs() < 0.01),
                      onTap: () => onSetCropAspect(opt.ratio),
                    ),
                ],
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    for (final opt in aspectOptions)
                      _AspectChip(
                        label: opt.label,
                        selected: opt.ratio == null
                            ? cropAspectRatio == null
                            : (cropAspectRatio != null &&
                                (cropAspectRatio! - opt.ratio!).abs() < 0.01),
                        onTap: () => onSetCropAspect(opt.ratio),
                      ),
                  ],
                ),
              ),
          ],
        );

      case EditorTool.draw:
      case EditorTool.redact:
        final colors = isLandscape
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final color in editorColorPalette)
                      _ColorSwatch(
                        color: color,
                        selected: color == currentColor,
                        onTap: () => onSetColor(color),
                      ),
                  ],
                ),
              )
            : SizedBox(
                height: 52,
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final color in editorColorPalette)
                            _ColorSwatch(
                              color: color,
                              selected: color == currentColor,
                              onTap: () => onSetColor(color),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            colors,
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _EditorActionButton(
                  icon: Icons.tune_rounded,
                  label: 'Stroke',
                  onPressed: onShowStrokeWidthPicker,
                ),
                const SizedBox(width: 12),
                _EditorActionButton(
                  icon: Icons.delete_outline_rounded,
                  label: 'Clear',
                  onPressed: hasAnnotations ? onClearAllAnnotations : null,
                  isDestructive: true,
                ),
              ],
            ),
          ],
        );

      case EditorTool.text:
        final colors = isLandscape
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final color in editorColorPalette)
                      _ColorSwatch(
                        color: color,
                        selected: color == currentColor,
                        onTap: () => onSetColor(color),
                      ),
                  ],
                ),
              )
            : SizedBox(
                height: 52,
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final color in editorColorPalette)
                            _ColorSwatch(
                              color: color,
                              selected: color == currentColor,
                              onTap: () => onSetColor(color),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            colors,
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _EditorActionButton(
                  icon: Icons.format_size_rounded,
                  label: 'Font Size',
                  onPressed: onShowFontSizePicker,
                ),
                const SizedBox(width: 12),
                _EditorActionButton(
                  icon: Icons.delete_outline_rounded,
                  label: 'Clear',
                  onPressed: hasAnnotations ? onClearAllAnnotations : null,
                  isDestructive: true,
                ),
              ],
            ),
          ],
        );

      case EditorTool.none:
        return const SizedBox(height: 8);
    }
  }
}
