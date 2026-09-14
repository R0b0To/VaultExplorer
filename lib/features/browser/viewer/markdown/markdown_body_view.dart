import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_ast.dart';
import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_parser.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/markdown_image.dart';

class MarkdownBodyView extends StatefulWidget {
  final String source;
  final MountedContainer container;
  final String currentFilePath;
  final void Function(String url) onLinkTap;
  final ScrollController? scrollController;
  final String? searchQuery;
  final int searchMatchIndex;
  final void Function(int totalMatches)? onMatchesFound;

  const MarkdownBodyView({
    super.key,
    required this.source,
    required this.container,
    required this.currentFilePath,
    required this.onLinkTap,
    this.scrollController,
    this.searchQuery,
    this.searchMatchIndex = 0,
    this.onMatchesFound,
  });

  @override
  State<MarkdownBodyView> createState() => MarkdownBodyViewState();
}

class MarkdownBodyViewState extends State<MarkdownBodyView> {
  final List<GlobalKey> _topLevelBlockKeys = [];
  List<int> _topLevelBlockLines = [];

  final List<GlobalKey> _headingKeysList = [];
  final Map<String, GlobalKey> _headingAnchorKeys = {};

  final List<GlobalKey> _searchMatchKeys = [];
  late ScrollController _scrollController;

  int _matchCounter = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
  }

  @override
  void didUpdateWidget(covariant MarkdownBodyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      if (oldWidget.scrollController == null) {
        _scrollController.dispose();
      }
      _scrollController = widget.scrollController ?? ScrollController();
    }

    if (oldWidget.searchMatchIndex != widget.searchMatchIndex &&
        widget.searchQuery != null &&
        widget.searchQuery!.isNotEmpty) {
      _scrollToActiveMatch();
    }
  }

  void _scrollToActiveMatch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.searchMatchIndex >= 0 &&
          widget.searchMatchIndex < _searchMatchKeys.length) {
        final key = _searchMatchKeys[widget.searchMatchIndex];
        if (key.currentContext != null) {
          Scrollable.ensureVisible(
            key.currentContext!,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: 0.2,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  void _handleLink(String url) {
    if (url.startsWith('#')) {
      final rawTarget = url.substring(1).trim();
      final decodedTarget = Uri.decodeComponent(rawTarget).toLowerCase();

      if (decodedTarget.isEmpty || decodedTarget == 'top') {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
        return;
      }

      final key = _resolveHeadingKey(decodedTarget);

      if (key?.currentContext != null) {
        final box = key!.currentContext!.findRenderObject() as RenderBox?;
        final scrollBox = context.findRenderObject() as RenderBox?;

        if (box != null && scrollBox != null && _scrollController.hasClients) {
          final targetOffset = box.localToGlobal(Offset.zero, ancestor: scrollBox).dy +
              _scrollController.offset -
              12;
          _scrollController.animateTo(
            targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
          );
          return;
        }

        Scrollable.ensureVisible(
          key.currentContext!,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          alignment: 0.05,
        );
        return;
      }
    }
    widget.onLinkTap(url);
  }

  GlobalKey? _resolveHeadingKey(String target) {
    final slug = _slugify(target);
    final alpha = target.replaceAll(RegExp(r'[^a-z0-9]'), '');

    if (_headingAnchorKeys.containsKey(slug)) return _headingAnchorKeys[slug];
    if (_headingAnchorKeys.containsKey(target)) return _headingAnchorKeys[target];
    if (alpha.isNotEmpty && _headingAnchorKeys.containsKey(alpha)) return _headingAnchorKeys[alpha];

    for (final entry in _headingAnchorKeys.entries) {
      final k = entry.key;
      if (k == slug || k == target) return entry.value;
      if (k.endsWith('-$slug') || k.startsWith('$slug-')) return entry.value;
      if (alpha.isNotEmpty && k.replaceAll('-', '').contains(alpha)) return entry.value;
      if (slug.isNotEmpty && k.contains(slug)) return entry.value;
    }
    return null;
  }

  static String _slugify(String text) {
    return text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-');
  }

  static String _plainTextOf(List<MdInline> inlines) {
    final sb = StringBuffer();
    for (final inline in inlines) {
      if (inline is MdText) {
        sb.write(inline.text);
      } else if (inline is MdInlineCode) {
        sb.write(inline.code);
      } else if (inline is MdBold) {
        sb.write(_plainTextOf(inline.children));
      } else if (inline is MdItalic) {
        sb.write(_plainTextOf(inline.children));
      } else if (inline is MdUnderline) {
        sb.write(_plainTextOf(inline.children));
      } else if (inline is MdHighlight) {
        sb.write(_plainTextOf(inline.children));
      } else if (inline is MdStrikethrough) {
        sb.write(_plainTextOf(inline.children));
      } else if (inline is MdSubscript) {
        sb.write(_plainTextOf(inline.children));
      } else if (inline is MdSuperscript) {
        sb.write(_plainTextOf(inline.children));
      } else if (inline is MdLink) {
        sb.write(_plainTextOf(inline.children));
      }
    }
    return sb.toString();
  }

  void scrollToLine(int line) {
    if (_topLevelBlockLines.isEmpty) return;

    int bestIdx = 0;
    int minDiff = (_topLevelBlockLines.first - line).abs();

    for (int i = 0; i < _topLevelBlockLines.length; i++) {
      final diff = (_topLevelBlockLines[i] - line).abs();
      if (diff < minDiff) {
        minDiff = diff;
        bestIdx = i;
      }
    }

    if (bestIdx < _topLevelBlockKeys.length) {
      final key = _topLevelBlockKeys[bestIdx];
      if (key.currentContext != null) {
        final box = key.currentContext!.findRenderObject() as RenderBox?;
        final scrollBox = context.findRenderObject() as RenderBox?;

        if (box != null && scrollBox != null && _scrollController.hasClients) {
          final blockTopInScrollable = box.localToGlobal(Offset.zero, ancestor: scrollBox).dy + _scrollController.offset;
          final targetOffset = (blockTopInScrollable - 12.0).clamp(0.0, _scrollController.position.maxScrollExtent);
          _scrollController.jumpTo(targetOffset);
        }
      }
    }
  }

  int? getFirstVisibleLine() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return null;
    final viewportTop = renderBox.localToGlobal(Offset.zero).dy;
    final probeY = viewportTop + 14.0;

    for (int i = 0; i < _topLevelBlockKeys.length; i++) {
      final ctx = _topLevelBlockKeys[i].currentContext;
      if (ctx != null) {
        final box = ctx.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          final top = box.localToGlobal(Offset.zero).dy;
          final bottom = top + box.size.height;
          if (top <= probeY && bottom > probeY) {
            return _topLevelBlockLines[i];
          }
        }
      }
    }
    return _topLevelBlockLines.isNotEmpty ? _topLevelBlockLines.first : 0;
  }

  @override
  Widget build(BuildContext context) {
    _matchCounter = 0;
    _headingAnchorKeys.clear();

    final blocks = parseMarkdownDocument(widget.source);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (blocks.isEmpty) {
      return Center(
        child: Text(
          context.l10n.markdownEmptyPreviewMessage,
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    while (_topLevelBlockKeys.length < blocks.length) {
      _topLevelBlockKeys.add(GlobalKey());
    }
    _topLevelBlockLines = blocks.map((b) => b.sourceLine).toList();

    int headingIndex = 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.onMatchesFound != null) {
        widget.onMatchesFound!(_matchCounter);
      }
    });

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < blocks.length; i++)
            KeyedSubtree(
              key: _topLevelBlockKeys[i],
              child: _buildBlock(
                context,
                blocks[i],
                textTheme,
                cs,
                depth: 0,
                onHeadingEncountered: () {
                  while (_headingKeysList.length <= headingIndex) {
                    _headingKeysList.add(GlobalKey());
                  }
                  return _headingKeysList[headingIndex++];
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBlock(
    BuildContext context,
    MdBlock block,
    TextTheme textTheme,
    ColorScheme cs, {
    int depth = 0,
    bool isFirstInListItem = false,
    GlobalKey Function()? onHeadingEncountered,
  }) {
    if (block is MdHeading) {
      final plainText = _plainTextOf(block.content);
      final baseSlug = _slugify(plainText);

      GlobalKey headingKey;
      if (onHeadingEncountered != null) {
        headingKey = onHeadingEncountered();
      } else {
        headingKey = GlobalKey();
      }

      String slug = baseSlug;
      int dup = 1;
      while (_headingAnchorKeys.containsKey(slug)) {
        slug = '$baseSlug-$dup';
        dup++;
      }
      _headingAnchorKeys[slug] = headingKey;

      final rawLower = plainText.toLowerCase().trim();
      if (!_headingAnchorKeys.containsKey(rawLower)) {
        _headingAnchorKeys[rawLower] = headingKey;
      }
      final alpha = rawLower.replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (alpha.isNotEmpty && !_headingAnchorKeys.containsKey(alpha)) {
        _headingAnchorKeys[alpha] = headingKey;
      }

      return KeyedSubtree(
        key: headingKey,
        child: Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: _inlineRichText(
            context,
            block.content,
            _headingStyle(textTheme, block.level),
            cs,
          ),
        ),
      );
    }
    if (block is MdParagraph) {
      return Padding(
        padding: EdgeInsets.only(
          top: isFirstInListItem ? 0 : 4,
          bottom: 4,
        ),
        child: _inlineRichText(
          context,
          block.content,
          textTheme.bodyMedium?.copyWith(height: 1.5),
          cs,
        ),
      );
    }
    if (block is MdCallout) {
      return _CalloutWidget(
        block: block,
        textTheme: textTheme,
        cs: cs,
        buildChild: (child) => _buildBlock(
          context,
          child,
          textTheme,
          cs,
          depth: depth,
          onHeadingEncountered: onHeadingEncountered,
        ),
      );
    }
    if (block is MdBlockquote) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
          border: Border(
            left: BorderSide(color: cs.primary.withValues(alpha: 0.7), width: 3.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final child in block.children)
              _buildBlock(
                context,
                child,
                textTheme,
                cs,
                depth: depth,
                onHeadingEncountered: onHeadingEncountered,
              ),
          ],
        ),
      );
    }
    if (block is MdCodeBlock) {
      return _CodeBlockWidget(block: block);
    }
    if (block is MdHorizontalRule) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Divider(color: cs.outlineVariant, thickness: 1),
      );
    }
    if (block is MdImageBlock) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _buildImage(context, block.alt, block.path, cs),
      );
    }
    if (block is MdList) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int idx = 0; idx < block.items.length; idx++)
              _buildListItem(
                context,
                block,
                block.items[idx],
                idx,
                textTheme,
                cs,
                depth: depth,
                onHeadingEncountered: onHeadingEncountered,
              ),
          ],
        ),
      );
    }
    if (block is MdTable) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _buildTable(context, block, textTheme, cs),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildListItem(
    BuildContext context,
    MdList list,
    MdListItem item,
    int index,
    TextTheme textTheme,
    ColorScheme cs, {
    required int depth,
    GlobalKey Function()? onHeadingEncountered,
  }) {
    Widget markerWidget;

    if (item.checked != null) {
      markerWidget = SizedBox(
        width: 22,
        height: 22,
        child: Center(
          child: Icon(
            item.checked!
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            size: 18,
            color: item.checked! ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      );
    } else if (list.ordered) {
      markerWidget = Container(
        width: 24,
        height: 22,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 6),
        child: Text(
          '${list.startNumber + index}.',
          style: textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    } else {
      final level = depth % 3;
      Widget bulletShape;
      if (level == 0) {
        bulletShape = Container(
          width: 5.5,
          height: 5.5,
          decoration: BoxDecoration(color: cs.onSurface, shape: BoxShape.circle),
        );
      } else if (level == 1) {
        bulletShape = Container(
          width: 5.5,
          height: 5.5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: cs.onSurface, width: 1.2),
          ),
        );
      } else {
        bulletShape = Container(
          width: 4.5,
          height: 4.5,
          decoration: BoxDecoration(color: cs.onSurfaceVariant),
        );
      }

      markerWidget = SizedBox(
        width: 22,
        height: 22,
        child: Center(child: bulletShape),
      );
    }

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int cIdx = 0; cIdx < item.children.length; cIdx++)
          _buildBlock(
            context,
            item.children[cIdx],
            textTheme,
            cs,
            depth: depth + 1,
            isFirstInListItem: cIdx == 0,
            onHeadingEncountered: onHeadingEncountered,
          ),
      ],
    );

    if (item.checked == true) {
      content = DefaultTextStyle.merge(
        style: TextStyle(
          decoration: TextDecoration.lineThrough,
          color: cs.onSurfaceVariant,
        ),
        child: content,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          markerWidget,
          const SizedBox(width: 4),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _buildTable(
    BuildContext context,
    MdTable table,
    TextTheme textTheme,
    ColorScheme cs,
  ) {
    final columnCount = table.headerCells.length;
    if (columnCount == 0) return const SizedBox.shrink();

    List<List<MdInline>> normalize(List<List<MdInline>> row) {
      if (row.length == columnCount) return row;
      if (row.length > columnCount) return row.sublist(0, columnCount);
      return [...row, for (int i = row.length; i < columnCount; i++) const <MdInline>[]];
    }

    TextAlign alignFor(int col) {
      if (col >= table.alignments.length) return TextAlign.left;
      return switch (table.alignments[col]) {
        MdTableAlign.center => TextAlign.center,
        MdTableAlign.right => TextAlign.right,
        MdTableAlign.left || MdTableAlign.none => TextAlign.left,
      };
    }

    Widget cell(List<MdInline> content, int col, {bool header = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: _inlineRichText(
          context,
          content,
          header
              ? textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)
              : textTheme.bodyMedium,
          cs,
          textAlign: alignFor(col),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        border: TableBorder.all(color: cs.outlineVariant, width: 0.6),
        defaultColumnWidth: const IntrinsicColumnWidth(),
        children: [
          TableRow(
            decoration: BoxDecoration(color: cs.surfaceContainerHighest),
            children: [
              for (int c = 0; c < columnCount; c++)
                cell(table.headerCells[c], c, header: true),
            ],
          ),
          for (final row in table.rows)
            TableRow(
              children: [
                for (int c = 0; c < columnCount; c++) cell(normalize(row)[c], c),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildImage(BuildContext context, String alt, String path, ColorScheme cs) {
    if (path.isEmpty) return const SizedBox.shrink();

    if (path.startsWith('http://') || path.startsWith('https://')) {
      return _RemoteImagePlaceholder(alt: alt, url: path, onTap: widget.onLinkTap);
    }

    final resolved = _resolveVaultPath(widget.currentFilePath, path);
    return MarkdownImage(
      container: widget.container,
      resolvedPath: resolved,
      alt: alt,
    );
  }

  static String _resolveVaultPath(String currentFilePath, String reference) {
    if (p.isAbsolute(reference)) return p.normalize(reference);
    final dir = p.dirname(currentFilePath);
    return p.normalize(p.join(dir, reference));
  }

  TextStyle _headingStyle(TextTheme textTheme, int level) {
    switch (level) {
      case 1:
        return textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold) ??
            const TextStyle(fontSize: 24, fontWeight: FontWeight.bold);
      case 2:
        return textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold) ??
            const TextStyle(fontSize: 20, fontWeight: FontWeight.bold);
      case 3:
        return textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold) ??
            const TextStyle(fontSize: 17, fontWeight: FontWeight.bold);
      case 4:
        return textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold) ??
            const TextStyle(fontSize: 15, fontWeight: FontWeight.bold);
      case 5:
        return textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold) ??
            const TextStyle(fontSize: 14, fontWeight: FontWeight.bold);
      default:
        return textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold) ??
            const TextStyle(fontSize: 13, fontWeight: FontWeight.bold);
    }
  }

  Widget _inlineRichText(
    BuildContext context,
    List<MdInline> nodes,
    TextStyle? baseStyle,
    ColorScheme cs, {
    TextAlign textAlign = TextAlign.start,
  }) {
    final style = baseStyle ?? const TextStyle();
    return Text.rich(
      TextSpan(children: _buildSpans(context, nodes, style, cs)),
      textAlign: textAlign,
    );
  }

  List<InlineSpan> _buildSpans(
    BuildContext context,
    List<MdInline> nodes,
    TextStyle style,
    ColorScheme cs,
  ) {
    final spans = <InlineSpan>[];
    final query = widget.searchQuery?.trim().toLowerCase();

    for (final node in nodes) {
      if (node is MdText) {
        if (query != null && query.isNotEmpty) {
          spans.addAll(_buildSearchHighlightedSpans(node.text, style, query, cs));
        } else {
          spans.add(TextSpan(text: node.text, style: style));
        }
      } else if (node is MdLineBreak) {
        spans.add(const TextSpan(text: '\n'));
      } else if (node is MdBold) {
        spans.add(
          TextSpan(
            children: _buildSpans(context, node.children, style.copyWith(fontWeight: FontWeight.bold), cs),
          ),
        );
      } else if (node is MdItalic) {
        spans.add(
          TextSpan(
            children: _buildSpans(context, node.children, style.copyWith(fontStyle: FontStyle.italic), cs),
          ),
        );
      } else if (node is MdUnderline) {
        spans.add(
          TextSpan(
            children: _buildSpans(context, node.children, style.copyWith(decoration: TextDecoration.underline), cs),
          ),
        );
      } else if (node is MdHighlight) {
        spans.add(
          TextSpan(
            children: _buildSpans(
              context,
              node.children,
              style.copyWith(
                backgroundColor: Colors.amber.withValues(alpha: 0.35),
                color: cs.onSurface,
              ),
              cs,
            ),
          ),
        );
      } else if (node is MdStrikethrough) {
        spans.add(
          TextSpan(
            children: _buildSpans(context, node.children, style.copyWith(decoration: TextDecoration.lineThrough), cs),
          ),
        );
      } else if (node is MdSubscript) {
        spans.add(
          TextSpan(
            children: _buildSpans(context, node.children, style.copyWith(fontSize: (style.fontSize ?? 14) * 0.8), cs),
          ),
        );
      } else if (node is MdSuperscript) {
        spans.add(
          TextSpan(
            children: _buildSpans(context, node.children, style.copyWith(fontSize: (style.fontSize ?? 14) * 0.8), cs),
          ),
        );
      } else if (node is MdInlineCode) {
        spans.add(
          TextSpan(
            text: node.code,
            style: style.copyWith(
              fontFamily: 'monospace',
              fontSize: (style.fontSize ?? 14) * 0.92,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
        );
      } else if (node is MdLink) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _handleLink(node.url),
                child: Text.rich(
                  TextSpan(
                    children: _buildSpans(
                      context,
                      node.children,
                      style.copyWith(
                        color: cs.primary,
                        decoration: TextDecoration.underline,
                      ),
                      cs,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      } else if (node is MdInlineImage) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(
              Icons.image_outlined,
              size: (style.fontSize ?? 14) + 2,
              color: cs.onSurfaceVariant,
            ),
          ),
        );
        spans.add(
          TextSpan(
            text: node.alt.isNotEmpty ? ' ${node.alt}' : ' image',
            style: style.copyWith(
              color: cs.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        );
      }
    }
    return spans;
  }

  List<InlineSpan> _buildSearchHighlightedSpans(
    String text,
    TextStyle baseStyle,
    String query,
    ColorScheme cs,
  ) {
    final spans = <InlineSpan>[];
    final lower = text.toLowerCase();
    int start = 0;

    while (true) {
      final index = lower.indexOf(query, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start), style: baseStyle));
        break;
      }

      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: baseStyle));
      }

      final matchIdx = _matchCounter++;
      while (_searchMatchKeys.length <= matchIdx) {
        _searchMatchKeys.add(GlobalKey());
      }
      final matchKey = _searchMatchKeys[matchIdx];

      final isCurrent = matchIdx == widget.searchMatchIndex;
      final matchedText = text.substring(index, index + query.length);

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: KeyedSubtree(
            key: matchKey,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isCurrent ? Colors.orange : Colors.yellow.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                matchedText,
                style: baseStyle.copyWith(
                  color: Colors.black,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      );

      start = index + query.length;
    }

    return spans;
  }
}

class _CodeBlockWidget extends StatefulWidget {
  final MdCodeBlock block;

  const _CodeBlockWidget({required this.block});

  @override
  State<_CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<_CodeBlockWidget> {
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.block.code));
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lang = widget.block.language?.trim();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  (lang != null && lang.isNotEmpty) ? lang : 'code',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                InkWell(
                  onTap: _copy,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copied ? Icons.check_rounded : Icons.copy_rounded,
                          size: 14,
                          color: _copied ? cs.primary : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? context.l10n.verbCopied : context.l10n.copy,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: _copied ? cs.primary : cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Text(
              widget.block.code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalloutWidget extends StatefulWidget {
  final MdCallout block;
  final TextTheme textTheme;
  final ColorScheme cs;
  final Widget Function(MdBlock child) buildChild;

  const _CalloutWidget({
    required this.block,
    required this.textTheme,
    required this.cs,
    required this.buildChild,
  });

  @override
  State<_CalloutWidget> createState() => _CalloutWidgetState();
}

class _CalloutWidgetState extends State<_CalloutWidget> {
  late bool _isCollapsed;

  @override
  void initState() {
    super.initState();
    _isCollapsed = widget.block.defaultCollapsed;
  }

  (Color, IconData, String) _styleForType(String type, ColorScheme cs) {
    switch (type.toLowerCase()) {
      case 'tip':
      case 'hint':
      case 'important':
        return (Colors.teal, Icons.lightbulb_outline_rounded, 'Tip');
      case 'warning':
      case 'caution':
      case 'attention':
        return (Colors.orange, Icons.warning_amber_rounded, 'Warning');
      case 'danger':
      case 'error':
      case 'bug':
      case 'fail':
        return (cs.error, Icons.error_outline_rounded, 'Danger');
      case 'success':
      case 'check':
      case 'done':
        return (Colors.green, Icons.check_circle_outline_rounded, 'Success');
      case 'question':
      case 'faq':
      case 'help':
        return (Colors.deepPurple, Icons.help_outline_rounded, 'Question');
      case 'quote':
      case 'cite':
        return (cs.outline, Icons.format_quote_rounded, 'Quote');
      case 'example':
        return (Colors.indigo, Icons.list_alt_rounded, 'Example');
      case 'todo':
        return (Colors.cyan, Icons.checklist_rounded, 'Todo');
      case 'note':
      case 'info':
      default:
        return (cs.primary, Icons.info_outline_rounded, 'Note');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (accentColor, iconData, defaultTitle) = _styleForType(widget.block.type, widget.cs);
    final displayTitle = widget.block.title.isNotEmpty ? widget.block.title : defaultTitle;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: accentColor, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: widget.block.collapsible
                ? () => setState(() => _isCollapsed = !_isCollapsed)
                : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(iconData, size: 18, color: accentColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      displayTitle,
                      style: widget.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                  ),
                  if (widget.block.collapsible)
                    Icon(
                      _isCollapsed ? Icons.chevron_right_rounded : Icons.expand_more_rounded,
                      size: 18,
                      color: accentColor,
                    ),
                ],
              ),
            ),
          ),
          if (!_isCollapsed && widget.block.children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final child in widget.block.children) widget.buildChild(child),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RemoteImagePlaceholder extends StatelessWidget {
  final String alt;
  final String url;
  final void Function(String url) onTap;

  const _RemoteImagePlaceholder({
    required this.alt,
    required this.url,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onTap(url),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.open_in_new_rounded, color: cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alt.isNotEmpty ? alt : url,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    url,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}