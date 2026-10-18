import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/entry_conflict.dart';
import 'package:vaultexplorer/core/filesystem/filesystem_type.dart';
import 'package:vaultexplorer/core/filesystem/illegal_char_input_formatter.dart';
import 'package:vaultexplorer/core/filesystem/mounted_container_filesystem.dart';
import 'package:vaultexplorer/core/filesystem/name_validation.dart';
import 'package:vaultexplorer/core/filesystem/path_components.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/inputs/password_visibility_toggle.dart';
import 'package:vaultexplorer/data/models/archive_models.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';


extension ArchiveCompressionLevelL10n on ArchiveCompressionLevel {
  String localizedTitle(AppLocalizations l10n) => switch (this) {
        ArchiveCompressionLevel.store => l10n.archiveCompressionStoreTitle,
        ArchiveCompressionLevel.fast => l10n.archiveCompressionFastTitle,
        ArchiveCompressionLevel.normal => l10n.archiveCompressionNormalTitle,
        ArchiveCompressionLevel.ultra => l10n.archiveCompressionUltraTitle,
      };

  String localizedDescription(AppLocalizations l10n) => switch (this) {
        ArchiveCompressionLevel.store => l10n.archiveCompressionStoreDesc,
        ArchiveCompressionLevel.fast => l10n.archiveCompressionFastDesc,
        ArchiveCompressionLevel.normal => l10n.archiveCompressionNormalDesc,
        ArchiveCompressionLevel.ultra => l10n.archiveCompressionUltraDesc,
      };
}

extension ArchiveCompressionMethodL10n on ArchiveCompressionMethod {
  /// What the method is good for and where else it is used. Empty for `auto`,
  /// which is never shown to the user.
  String localizedDescription(AppLocalizations l10n) => switch (this) {
        ArchiveCompressionMethod.auto => '',
        ArchiveCompressionMethod.lzma2 => l10n.archiveMethodLzma2Desc,
        ArchiveCompressionMethod.lzma => l10n.archiveMethodLzmaDesc,
        ArchiveCompressionMethod.deflate => l10n.archiveMethodDeflateDesc,
      };
}

/// A modal bottom sheet for creating archives with modern layout, decoupled
/// name/extension, dynamic security options, and a compression level picker
/// that only appears for formats that actually compress.
class CreateArchiveBottomSheet extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String currentDirPath;
  final List<RawEntry> existingEntries;
  final String suggestedName;
  final List<RawEntry> selectedEntries;
  final int? freeSpace;
  final Future<void> Function(
    String destPathInContainer,
    ArchiveFormatType format,
    String? passphrase,
    bool encryptFilenames,
    ArchiveCompressionLevel compressionLevel,
    ArchiveCompressionMethod compressionMethod,
    int splitSizeBytes,
  ) onCreate;

  const CreateArchiveBottomSheet({
    super.key,
    required this.container,
    required this.currentDirPath,
    required this.existingEntries,
    required this.suggestedName,
    this.selectedEntries = const [],
    this.freeSpace,
    required this.onCreate,
  });

  static Future<void> show(
    BuildContext context, {
    required MountedContainer container,
    required String currentDirPath,
    required List<RawEntry> existingEntries,
    required String suggestedName,
    List<RawEntry> selectedEntries = const [],
    int? freeSpace,
    required Future<void> Function(
      String destPathInContainer,
      ArchiveFormatType format,
      String? passphrase,
      bool encryptFilenames,
      ArchiveCompressionLevel compressionLevel,
      ArchiveCompressionMethod compressionMethod,
      int splitSizeBytes,
    ) onCreate,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (sheetContext) => CreateArchiveBottomSheet(
        container: container,
        currentDirPath: currentDirPath,
        existingEntries: existingEntries,
        suggestedName: suggestedName,
        selectedEntries: selectedEntries,
        freeSpace: freeSpace,
        onCreate: onCreate,
      ),
    );
  }

  @override
  ConsumerState<CreateArchiveBottomSheet> createState() =>
      _CreateArchiveBottomSheetState();
}

class _CreateArchiveBottomSheetState
    extends ConsumerState<CreateArchiveBottomSheet> {
  static const _selectableFormats = [
    ArchiveFormatType.zip,
    ArchiveFormatType.sevenZip,
    ArchiveFormatType.tar,
    ArchiveFormatType.tarGz,
    ArchiveFormatType.tarXz,
    ArchiveFormatType.tarZstd,
  ];

  late final TextEditingController _nameCtrl;
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _confirmPasswordCtrl = TextEditingController();
  late final FilesystemType _fsType;
  ArchiveFormatType _format = ArchiveFormatType.zip;
  ArchiveCompressionLevel _compressionLevel = ArchiveCompressionLevel.normal;
  // The user's pick for formats that offer one (7z). Kept across format
  // switches so going 7z -> ZIP -> 7z doesn't forget it; what is actually sent
  // is [_effectiveMethod].
  ArchiveCompressionMethod _method =
      ArchiveFormatType.sevenZip.selectableCompressionMethods.first;

  // Split into parts (ZIP / 7z): 0 = one file. [_splitCustom] means the size
  // comes from [_splitCustomCtrl] (in MB) instead of one of the presets.
  static const _mb = 1024 * 1024;
  // The largest part that still fits a FAT32 file (4 GiB - 1 byte).
  static const _fat32PartMb = 4095;
  static const _splitPresetsMb = [100, 500, 1024, _fat32PartMb];
  int _splitSizeBytes = 0;
  bool _splitCustom = false;
  final TextEditingController _splitCustomCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _encryptFilenames = false;
  bool _isMediaRecommended = false;

  List<NameValidationIssue> _issues = [];
  EntryConflictResult _conflict =
      const EntryConflictResult(EntryConflictKind.none, null);

  int get _totalSelectedBytes =>
      widget.selectedEntries.fold<int>(0, (sum, e) => sum + e.sizeBytes);

  bool get _hasPassword =>
      _format.supportsPassword && _passwordCtrl.text.isNotEmpty;

  bool get _passwordMatchesConfirm =>
      !_hasPassword || _passwordCtrl.text == _confirmPasswordCtrl.text;

  bool get _isValidName => _issues.isEmpty && !_conflict.isConflict;

  /// Store really stores only in ZIP and 7z. On the compressed TARs level 0
  /// just means that filter's fastest setting, so it still has a codec.
  bool get _isStoring =>
      _compressionLevel == ArchiveCompressionLevel.store &&
      (_format == ArchiveFormatType.zip ||
          _format == ArchiveFormatType.sevenZip);

  /// Whether the user can choose the codec right now: the format offers a
  /// choice and it isn't being stored (no compression, so no codec).
  bool get _canPickMethod =>
      _format.selectableCompressionMethods.isNotEmpty && !_isStoring;

  /// The method sent to the engine. `auto` whenever the user had no say, so the
  /// engine never sees a method its format can't write.
  ArchiveCompressionMethod get _effectiveMethod =>
      _canPickMethod ? _method : ArchiveCompressionMethod.auto;

  /// The custom part size in MB, or null when the field is not a whole number
  /// between 1 MB and the FAT32 limit.
  int? get _customSplitMb {
    final mb = int.tryParse(_splitCustomCtrl.text.trim());
    if (mb == null || mb < 1 || mb > _fat32PartMb) return null;
    return mb;
  }

  /// Part size to create with; 0 = a single file.
  int get _effectiveSplitBytes {
    if (!_format.supportsSplit) return 0;
    if (_splitCustom) return (_customSplitMb ?? 0) * _mb;
    return _splitSizeBytes;
  }

  bool get _splitValid => !_splitCustom || !_format.supportsSplit || _customSplitMb != null;

  bool get _hasEnoughSpace {
    if (widget.freeSpace == null || widget.freeSpace! < 0) return true;
    return widget.freeSpace! >= _totalSelectedBytes;
  }

  bool get _canCreate {
    final stem = _nameCtrl.text.trim();
    if (stem.isEmpty) return false;
    if (!_isValidName) return false;
    if (!_hasEnoughSpace) return false;
    if (!_passwordMatchesConfirm) return false;
    if (!_splitValid) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    _fsType = resolveFilesystemType(widget.container);

    // Decouple name and extension: extract stem without extension
    final initialSuggested = widget.suggestedName;
    final dotIdx = initialSuggested.lastIndexOf('.');
    final stem = dotIdx > 0
        ? initialSuggested.substring(0, dotIdx)
        : initialSuggested;
    _nameCtrl = TextEditingController(text: stem);

    // Smart recommendation: check if only media/precompressed files are selected
    if (_hasOnlyPrecompressedFiles(widget.selectedEntries)) {
      _compressionLevel = ArchiveCompressionLevel.store;
      _isMediaRecommended = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _revalidate();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _splitCustomCtrl.dispose();
    super.dispose();
  }

  static bool _hasOnlyPrecompressedFiles(List<RawEntry> entries) {
    if (entries.isEmpty) return false;
    const precompressedExtensions = {
      'mp4', 'mkv', 'avi', 'mov', 'webm', '3gp', 'flv', 'wmv', 'm4v',
      'mp3', 'm4a', 'aac', 'ogg', 'opus', 'flac', 'wma',
      'jpg', 'jpeg', 'png', 'webp', 'heic', 'gif',
      'zip', '7z', 'rar', 'gz', 'tgz', 'bz2', 'xz', 'zst', 'tar.gz', 'apk', 'pdf'
    };
    final fileEntries = entries.where((e) => !e.isDir).toList();
    if (fileEntries.isEmpty) return false;
    return fileEntries.every((e) {
      final dot = e.name.lastIndexOf('.');
      if (dot == -1) return false;
      final ext = e.name.substring(dot + 1).toLowerCase();
      return precompressedExtensions.contains(ext);
    });
  }

  void _revalidate() {
    final stem = _nameCtrl.text.trim();
    final fullName = stem.isEmpty ? '' : '$stem.${_format.fileExtension}';
    final l10n = context.l10n;

    final nameResult = validateEntryName(
      fullName,
      _fsType,
      entryType: EntryType.file,
      l10n: l10n,
    );

    final conflictResult = fullName.isEmpty
        ? const EntryConflictResult(EntryConflictKind.none, null)
        : checkEntryConflict(
            candidateName: fullName,
            candidateIsDir: false,
            existingEntries: widget.existingEntries,
            caseSensitive: FilesystemRules.of(_fsType).caseSensitive,
          );

    setState(() {
      _issues = nameResult.issues;
      _conflict = conflictResult;
    });
  }

  void _onFormatChanged(ArchiveFormatType format) {
    if (format == _format) return;
    setState(() {
      _format = format;
      if (!format.supportsPassword) {
        _passwordCtrl.clear();
        _confirmPasswordCtrl.clear();
      }
      if (!format.supportsFilenameEncryption) {
        _encryptFilenames = false;
      }
      if (!format.supportsSplit) {
        _splitSizeBytes = 0;
        _splitCustom = false;
      }
    });
    _revalidate();
  }

  void _onCreate() {
    if (!_canCreate) return;
    final stem = _nameCtrl.text.trim();
    final fullName = '$stem.${_format.fileExtension}';
    final l10n = context.l10n;
    final parentSegments = widget.currentDirPath.isEmpty
        ? <String>[]
        : widget.currentDirPath.split('/');

    final built = PathComponents(
      parentSegments: parentSegments,
      name: fullName,
      type: EntryType.file,
      fsType: _fsType,
    ).validateAndBuild(l10n);
    if (built is! PathBuildSuccess) return;

    final passphrase = _hasPassword ? _passwordCtrl.text : null;
    final encryptFilenames =
        passphrase != null && _format.supportsFilenameEncryption && _encryptFilenames;

    Navigator.pop(context);
    widget.onCreate(
      built.path,
      _format,
      passphrase,
      encryptFilenames,
      _compressionLevel,
      _effectiveMethod,
      _effectiveSplitBytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.88;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: viewInsetsBottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildHeader(cs, textTheme),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),

              // ── Scrollable Form Body ────────────────────────────────────
              Flexible(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [

                      // Free space warning if insufficient
                      if (!_hasEnoughSpace) ...[
                        _buildInsufficientSpaceBanner(cs, textTheme),
                        const SizedBox(height: 12),
                      ],

                      // Archive Name & Decoupled Format Pill
                      _buildNameAndFormatRow(cs, textTheme),

                      // Live validation issues & conflict errors
                      _buildValidationIssues(cs),

                      // Dynamic Password & Security Options
                      if (_format.supportsPassword) ...[
                        const SizedBox(height: 12),
                        _buildSecuritySection(cs, textTheme),
                      ],

                      // Compression level, only for formats that compress
                      if (_format.supportsCompressionLevel) ...[
                        const SizedBox(height: 12),
                        _buildCompressionSection(cs, textTheme),
                        const SizedBox(height: 12),
                        _buildCompressionMethodSection(cs, textTheme),
                      ],

                      // Split into parts, only for formats that can be spanned
                      if (_format.supportsSplit) ...[
                        const SizedBox(height: 12),
                        _buildSplitSection(cs, textTheme),
                      ],
                    ],
                  ),
                ),
              ),

              // ── Bottom Action Buttons ───────────────────────────────────
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.l10n.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _canCreate ? _onCreate : null,
                      child: Text(context.l10n.create),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, TextTheme textTheme) {
    final count = widget.selectedEntries.length;
    final totalSizeStr = formatBytes(_totalSelectedBytes);

    final summaryText = count > 0
        ? context.l10n.createArchiveCompressingSubtitle(
            context.l10n.fileOpItemsCount(count),
            totalSizeStr,
          )
        : context.l10n.createArchiveTitle;

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.archive_rounded, color: cs.primary, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.createArchiveTitle,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                summaryText,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInsufficientSpaceBanner(ColorScheme cs, TextTheme textTheme) {
    final requiredStr = formatBytes(_totalSelectedBytes);
    final freeStr = formatBytes(widget.freeSpace ?? 0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: cs.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.l10n.createArchiveInsufficientSpace(requiredStr, freeStr),
              style: textTheme.bodySmall?.copyWith(
                color: cs.onErrorContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildNameAndFormatRow(ColorScheme cs, TextTheme textTheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Name field (stem only)
        Expanded(
          child: TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: context.l10n.createArchiveNameLabel,
              hintText: context.l10n.createArchiveNameHint,
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.primary, width: 2),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            inputFormatters: [IllegalCharacterInputFormatter(_fsType)],
            onChanged: (_) => _revalidate(),
            onSubmitted: (_) => _onCreate(),
          ),
        ),
        const SizedBox(width: 8),

        // Dynamic extension pill / dropdown
        _buildFormatSelectorPill(cs, textTheme),
      ],
    );
  }

  Widget _buildFormatSelectorPill(ColorScheme cs, TextTheme textTheme) {
    return PopupMenuButton<ArchiveFormatType>(
      initialValue: _format,
      tooltip: context.l10n.createArchiveSelectFormatTooltip,
      onSelected: _onFormatChanged,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) => [
        for (final f in _selectableFormats)
          PopupMenuItem(
            value: f,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '.${f.fileExtension}',
                    style: TextStyle(
                      fontWeight: f == _format ? FontWeight.bold : FontWeight.normal,
                      color: f == _format ? cs.primary : cs.onSurface,
                    ),
                  ),
                ),
                if (f == _format)
                  Icon(Icons.check, size: 18, color: cs.primary),
              ],
            ),
          ),
      ],
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '.${_format.fileExtension}',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.primary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildValidationIssues(ColorScheme cs) {
    final candidateName = '${_nameCtrl.text.trim()}.${_format.fileExtension}';
    final hasIssues = _issues.isNotEmpty || _conflict.isConflict;
    final messages = hasIssues
        ? [
            ..._issues.map((i) => i.message),
            if (_conflict.isConflict)
              _conflict.message(context.l10n, candidateName)!,
          ]
        : const <String>[];

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: hasIssues
          ? Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: messages
                    .map((m) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            m,
                            style: TextStyle(
                              color: cs.error,
                              fontSize: 12,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildSecuritySection(ColorScheme cs, TextTheme textTheme) {
    final hasPassword = _passwordCtrl.text.isNotEmpty;
    final hasConfirmMismatch =
        hasPassword && _passwordCtrl.text != _confirmPasswordCtrl.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Password field
        TextField(
          controller: _passwordCtrl,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: context.l10n.createArchivePasswordLabel,
            hintText: context.l10n.createArchivePasswordHintText,
            filled: true,
            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            suffixIcon: PasswordVisibilityToggle(
              obscured: _obscurePassword,
              onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),

        // Password strength meter & Repeat password field when entered
        if (hasPassword) ...[
          const SizedBox(height: 8),
          _buildPasswordStrengthBar(cs, textTheme),
          const SizedBox(height: 10),
          TextField(
            controller: _confirmPasswordCtrl,
            obscureText: _obscureConfirmPassword,
            decoration: InputDecoration(
              labelText: context.l10n.createArchiveConfirmPasswordLabel,
              hintText: context.l10n.createArchiveConfirmPasswordHint,
              errorText: hasConfirmMismatch ? context.l10n.passwordsDoNotMatch : null,
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.primary, width: 2),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              suffixIcon: PasswordVisibilityToggle(
                obscured: _obscureConfirmPassword,
                onToggle: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],

        if (_format.supportsFilenameEncryption) ...[
          const SizedBox(height: 10),

          // Encrypt file names Action Tile / Switch
          _buildEncryptFilenamesTile(cs, textTheme),
        ],
      ],
    );
  }

  Widget _buildPasswordStrengthBar(ColorScheme cs, TextTheme textTheme) {
    final pwd = _passwordCtrl.text;
    int strength = 0;
    if (pwd.length >= 6) strength++;
    if (pwd.length >= 10) strength++;
    if (RegExp(r'[0-9]').hasMatch(pwd) && RegExp(r'[a-zA-Z]').hasMatch(pwd)) {
      strength++;
    }
    if (RegExp(r'[^a-zA-Z0-9]').hasMatch(pwd)) strength++;

    final (color, label) = switch (strength) {
      0 || 1 => (cs.error, context.l10n.passphraseStrengthWeak),
      2 => (Colors.orange, context.l10n.passphraseStrengthFair),
      3 => (cs.primary, context.l10n.passphraseStrengthGood),
      _ => (Colors.green, context.l10n.passphraseStrengthStrong),
    };

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (strength + 1) / 5.0,
              color: color,
              backgroundColor: cs.outlineVariant.withValues(alpha: 0.3),
              minHeight: 4,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildEncryptFilenamesTile(ColorScheme cs, TextTheme textTheme) {
    final hasPassword = _passwordCtrl.text.isNotEmpty;
    final canToggle = hasPassword;

    final subtitle = !hasPassword
        ? context.l10n.createArchiveEncryptFilenamesNeedsPassword
        : context.l10n.createArchiveEncryptFilenamesActive;

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.enhanced_encryption_rounded,
              color: canToggle
                  ? (_encryptFilenames ? cs.primary : cs.onSurfaceVariant)
                  : cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.createArchiveEncryptFilenames,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: canToggle
                          ? cs.onSurface
                          : cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: hasPassword && _encryptFilenames,
              onChanged:
                  canToggle ? (v) => setState(() => _encryptFilenames = v) : null,
            ),
          ],
        ),
      ),
    );
  }

  static String _splitPresetLabel(int mb) {
    if (mb == _fat32PartMb) return '4 GB (FAT32)';
    return mb % 1024 == 0 ? '${mb ~/ 1024} GB' : '$mb MB';
  }

  Widget _buildSplitSection(ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;
    final isZip = _format == ArchiveFormatType.zip;
    final active = _splitCustom || _splitSizeBytes > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.createArchiveSplitVolumes,
          style: textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ChoiceChip(
              label: Text(l10n.createArchiveSplitVolumeNone),
              selected: !active,
              onSelected: (_) => setState(() {
                _splitSizeBytes = 0;
                _splitCustom = false;
              }),
            ),
            for (final mb in _splitPresetsMb)
              ChoiceChip(
                label: Text(_splitPresetLabel(mb)),
                selected: !_splitCustom && _splitSizeBytes == mb * _mb,
                onSelected: (_) => setState(() {
                  _splitSizeBytes = mb * _mb;
                  _splitCustom = false;
                }),
              ),
            ChoiceChip(
              label: Text(l10n.splitChunkSizeCustom),
              selected: _splitCustom,
              onSelected: (_) => setState(() {
                _splitCustom = true;
                _splitSizeBytes = 0;
              }),
            ),
          ],
        ),
        if (_splitCustom) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _splitCustomCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              labelText: l10n.createArchiveCustomVolumeSizeLabel,
              hintText: l10n.createArchiveCustomVolumeSizeHint,
              errorText: _splitCustomCtrl.text.isNotEmpty && _customSplitMb == null
                  ? '1 – $_fat32PartMb'
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
        if (active)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              isZip ? l10n.createArchiveSplitHintZip : l10n.createArchiveSplitHintSevenZip,
              style: textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCompressionSection(ColorScheme cs, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<ArchiveCompressionLevel>(
          initialValue: _compressionLevel,
          isDense: true,
          decoration: InputDecoration(
            labelText: context.l10n.createArchiveCompressionLevel,
            filled: true,
            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          items: [
            for (final lvl in ArchiveCompressionLevel.values)
              DropdownMenuItem(
                value: lvl,
                child: Text(lvl.localizedTitle(context.l10n)),
              ),
          ],
          onChanged: (lvl) {
            if (lvl != null) {
              setState(() {
                _compressionLevel = lvl;
                _isMediaRecommended = false;
              });
            }
          },
        ),
      ],
    );
  }

  /// Where each codec is available, and when it can be chosen:
  ///  * 7z: a picker (LZMA2 / LZMA / Deflate), disabled while the level is Store.
  ///  * every other compressing format: a read-only line naming its one codec,
  ///    with a pointer to 7z when the user might be after LZMA.
  Widget _buildCompressionMethodSection(ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;
    final methods = _format.selectableCompressionMethods;

    if (_isStoring) {
      return _buildMethodNote(cs, textTheme, l10n.archiveMethodStoreNote);
    }

    if (methods.isEmpty) {
      final fixed = _format.fixedCompressionLabel;
      if (fixed == null) return const SizedBox.shrink();
      final showSevenZipHint = _format != ArchiveFormatType.tarXz &&
          _format != ArchiveFormatType.tarLzma;
      return _buildMethodNote(
        cs,
        textTheme,
        [
          l10n.archiveMethodFixedInfo(_format.displayLabel, fixed),
          if (showSevenZipHint) l10n.archiveMethodMoreInSevenZip,
        ].join(' '),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<ArchiveCompressionMethod>(
          initialValue: _method,
          isDense: true,
          decoration: InputDecoration(
            labelText: l10n.archiveCompressionMethodLabel,
            filled: true,
            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          items: [
            for (final m in methods)
              DropdownMenuItem(value: m, child: Text(m.displayLabel)),
          ],
          onChanged: (m) {
            if (m != null) setState(() => _method = m);
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: Text(
            _method.localizedDescription(l10n),
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _buildMethodNote(ColorScheme cs, TextTheme textTheme, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
