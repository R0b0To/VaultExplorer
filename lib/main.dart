import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';

void main() {
  runApp(const CryptBridgeApp());
}

// ─────────────────────────────────────────────
// App Root
// ─────────────────────────────────────────────

class CryptBridgeApp extends StatelessWidget {
  const CryptBridgeApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CryptBridge',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const VaultDashboard(),
    );
  }

  ThemeData _buildTheme() {
    const bg = Color(0xFF0D0F12);
    const surface = Color(0xFF161A1F);
    const surfaceVariant = Color(0xFF1E2329);
    const border = Color(0xFF2A3040);
    const accent = Color(0xFF4FC3F7); // cool cyan
    const accentDim = Color(0xFF1A3A4A);
    const textPrimary = Color(0xFFE8EDF2);
    const textSecondary = Color(0xFF7A8899);
    const errorColor = Color(0xFFEF5350);
    const successColor = Color(0xFF26C6DA);

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        background: bg,
        surface: surface,
        surfaceVariant: surfaceVariant,
        primary: accent,
        primaryContainer: accentDim,
        onPrimary: bg,
        onSurface: textPrimary,
        outline: border,
        error: errorColor,
      ),
      fontFamily: 'monospace',
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPrimary,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'monospace',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: textPrimary,
        ),
        iconTheme: IconThemeData(color: textSecondary),
      ),
      cardTheme: CardThemeData(
  color: surface,
  elevation: 0,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(8),
    side: const BorderSide(color: border, width: 1),
  ),
  margin: EdgeInsets.zero,
),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 13),
        hintStyle: const TextStyle(color: Color(0xFF4A5568), fontSize: 13),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 0,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: textPrimary, fontSize: 14),
        bodyMedium: TextStyle(color: textPrimary, fontSize: 13),
        bodySmall: TextStyle(color: textSecondary, fontSize: 12),
        labelLarge: TextStyle(
          color: textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        titleMedium: TextStyle(
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceVariant,
        contentTextStyle: const TextStyle(color: textPrimary, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: border),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Data Model
// ─────────────────────────────────────────────

class MountedContainer {
  final String uri;
  final String displayName;
  final int volId;
  final String password;
  final int pim;
  final List<String> rootFiles;
  final DateTime mountedAt;

  const MountedContainer({
    required this.uri,
    required this.displayName,
    required this.volId,
    required this.password,
    required this.pim,
    required this.rootFiles,
    required this.mountedAt,
  });

  MountedContainer copyWith({List<String>? rootFiles}) {
    return MountedContainer(
      uri: uri,
      displayName: displayName,
      volId: volId,
      password: password,
      pim: pim,
      rootFiles: rootFiles ?? this.rootFiles,
      mountedAt: mountedAt,
    );
  }
}

// ─────────────────────────────────────────────
// Platform Channel
// ─────────────────────────────────────────────

class CryptBridgeApi {
  static const _channel = MethodChannel('com.example.cryptbridge/engine');

  static Future<String?> pickContainer() =>
      _channel.invokeMethod<String>('pickContainer');

  /// Returns a record of (volId, files) on success, or null on auth failure.
  static Future<({int volId, List<String> files})?> unlockContainer(
      String filePath, String password, int pim) async {
    // invokeMethod<Map> — channel now returns {volId: Int, files: List<String>}
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('unlockContainer', {
      'filePath': filePath,
      'password': password,
      'pim': pim,
    });
    if (raw == null) return null;
    final volId = raw['volId'] as int;
    final files = (raw['files'] as List<Object?>).cast<String>();
    return (volId: volId, files: files);
  }

  static Future<bool> lockContainer(String filePath) async {
    final result = await _channel.invokeMethod<bool>('lockContainer', {
      'filePath': filePath,
    });
    return result ?? false;
  }

  static Future<bool> decryptFile(String filePath, String password, int pim,
      String fileName, String destPath) async {
    final result = await _channel.invokeMethod<bool>('decryptFile', {
      'filePath': filePath,
      'password': password,
      'pim': pim,
      'fileName': fileName,
      'destPath': destPath,
    });
    return result ?? false;
  }
}

// ─────────────────────────────────────────────
// Dashboard Screen
// ─────────────────────────────────────────────

class VaultDashboard extends StatefulWidget {
  const VaultDashboard({Key? key}) : super(key: key);

  @override
  State<VaultDashboard> createState() => _VaultDashboardState();
}

class _VaultDashboardState extends State<VaultDashboard> {
  final List<MountedContainer> _containers = [];

  void _onContainerMounted(MountedContainer container) {
    setState(() => _containers.add(container));
  }

  void _onContainerLocked(int volId) {
    setState(() => _containers.removeWhere((c) => c.volId == volId));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.lock_outline, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            const Text('CryptBridge'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _containers.length < 4
                ? _AddButton(onMounted: _onContainerMounted)
                : Tooltip(
                    message: 'Maximum 4 containers',
                    child: Icon(Icons.add, color: cs.outline),
                  ),
          ),
        ],
      ),
      body: _containers.isEmpty
          ? _EmptyState(onAdd: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => UnlockSheet(onMounted: _onContainerMounted),
              );
            })
          : _ContainerList(
              containers: _containers,
              onLocked: _onContainerLocked,
            ),
    );
  }
}

// ─────────────────────────────────────────────
// Add Button (in AppBar)
// ─────────────────────────────────────────────

class _AddButton extends StatelessWidget {
  final ValueChanged<MountedContainer> onMounted;
  const _AddButton({required this.onMounted});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => UnlockSheet(onMounted: onMounted),
      ),
      icon: const Icon(Icons.add),
      tooltip: 'Mount container',
    );
  }
}

// ─────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: cs.outline, width: 1),
              color: cs.surface,
            ),
            child: Icon(Icons.lock_outline, size: 32, color: cs.primary),
          ),
          const SizedBox(height: 20),
          Text('No containers mounted',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('Mount a VeraCrypt container to browse its files',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.folder_open, size: 16),
            label: const Text('Mount Container'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Container List
// ─────────────────────────────────────────────

class _ContainerList extends StatelessWidget {
  final List<MountedContainer> containers;
  final ValueChanged<int> onLocked;

  const _ContainerList({required this.containers, required this.onLocked});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: containers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _ContainerCard(
        container: containers[i],
        onLocked: onLocked,
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Container Card
// ─────────────────────────────────────────────

class _ContainerCard extends StatelessWidget {
  final MountedContainer container;
  final ValueChanged<int> onLocked;

  const _ContainerCard({required this.container, required this.onLocked});

  String _timeSince(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fileCount =
        container.rootFiles.where((f) => !f.startsWith('[DIR]')).length;
    final dirCount =
        container.rootFiles.where((f) => f.startsWith('[DIR]')).length;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FileBrowserScreen(container: container),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.lock_open, size: 18, color: cs.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(container.displayName,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text('Volume ${container.volId} · mounted ${_timeSince(container.mountedAt)}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  _LockButton(
                    container: container,
                    onLocked: onLocked,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 12),
              Row(
                children: [
                  _StatChip(
                    icon: Icons.insert_drive_file_outlined,
                    label: '$fileCount file${fileCount != 1 ? 's' : ''}',
                  ),
                  const SizedBox(width: 10),
                  _StatChip(
                    icon: Icons.folder_outlined,
                    label: '$dirCount folder${dirCount != 1 ? 's' : ''}',
                  ),
                  const Spacer(),
                  Text(
                    'Browse →',
                    style: TextStyle(
                      color: cs.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: cs.outline),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Lock Button
// ─────────────────────────────────────────────

class _LockButton extends StatefulWidget {
  final MountedContainer container;
  final ValueChanged<int> onLocked;
  const _LockButton({required this.container, required this.onLocked});

  @override
  State<_LockButton> createState() => _LockButtonState();
}

class _LockButtonState extends State<_LockButton> {
  bool _loading = false;

  Future<void> _lock() async {
    setState(() => _loading = true);
    try {
      await CryptBridgeApi.lockContainer(widget.container.uri);
      widget.onLocked(widget.container.volId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lock failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _loading ? null : _lock,
      tooltip: 'Lock container',
      icon: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.lock_outline,
              size: 20, color: Theme.of(context).colorScheme.error),
    );
  }
}

// ─────────────────────────────────────────────
// Unlock Sheet (Bottom Sheet)
// ─────────────────────────────────────────────

class UnlockSheet extends StatefulWidget {
  final ValueChanged<MountedContainer> onMounted;
  const UnlockSheet({Key? key, required this.onMounted}) : super(key: key);

  @override
  State<UnlockSheet> createState() => _UnlockSheetState();
}

class _UnlockSheetState extends State<UnlockSheet> {
  final _passwordCtrl = TextEditingController();
  final _pimCtrl = TextEditingController();
  String? _selectedUri;
  String? _selectedName;
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _pimCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final uri = await CryptBridgeApi.pickContainer();
      if (uri != null) {
        setState(() {
          _selectedUri = uri;
          _selectedName = uri.split('/').last.split('%2F').last;
          _error = null;
        });
      }
    } catch (e) {
      setState(() => _error = 'File picker failed: $e');
    }
  }

  Future<void> _unlock() async {
    if (_selectedUri == null) {
      setState(() => _error = 'Select a container first');
      return;
    }
    if (_passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Password is required');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final pim =
          _pimCtrl.text.isEmpty ? 0 : int.tryParse(_pimCtrl.text) ?? 0;
      final result = await CryptBridgeApi.unlockContainer(
          _selectedUri!, _passwordCtrl.text, pim);

      if (result != null) {
        final name = Uri.decodeFull(_selectedName ?? 'Container');

        widget.onMounted(MountedContainer(
          uri: _selectedUri!,
          displayName: name,
          volId: result.volId,
          password: _passwordCtrl.text,
          pim: pim,
          rootFiles: result.files,
          mountedAt: DateTime.now(),
        ));

        if (mounted) Navigator.pop(context);
      } else {
        setState(() => _error = 'Incorrect password or invalid container');
      }
    } on PlatformException catch (e) {
      setState(() => _error = e.message ?? 'Unknown error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);

    return Container(
      margin: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border.all(color: cs.outline.withOpacity(0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Text('Mount Container',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 17,
                      )),
              const SizedBox(height: 20),

              // File picker
              GestureDetector(
                onTap: _pickFile,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: cs.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _selectedUri != null
                          ? cs.primary.withOpacity(0.5)
                          : cs.outline,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _selectedUri != null
                            ? Icons.description_outlined
                            : Icons.folder_open,
                        size: 18,
                        color: _selectedUri != null ? cs.primary : cs.outline,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _selectedName ?? 'Select VeraCrypt container…',
                          style: TextStyle(
                            color: _selectedUri != null
                                ? cs.onSurface
                                : cs.outline,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_selectedUri != null)
                        Icon(Icons.check_circle,
                            size: 16, color: cs.primary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Password
              TextField(
                controller: _passwordCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.key_outlined, size: 18),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // PIM
              TextField(
                controller: _pimCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'PIM  (leave blank for default)',
                  prefixIcon: Icon(Icons.tune, size: 18),
                ),
              ),

              // Error
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: cs.error.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, size: 16, color: cs.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style:
                                TextStyle(color: cs.error, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              FilledButton(
                onPressed: _loading ? null : _unlock,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(Colors.white)),
                      )
                    : const Text('Unlock',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// File Browser Screen
// ─────────────────────────────────────────────

/// A single item in the virtual path we're browsing.
class _PathSegment {
  final String label;
  final String fatPath; // e.g. "Documents/Work"
  const _PathSegment(this.label, this.fatPath);
}

class FileBrowserScreen extends StatefulWidget {
  final MountedContainer container;

  const FileBrowserScreen({Key? key, required this.container})
      : super(key: key);

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  // Navigation stack — each entry represents a directory level.
  // items[last] is the currently visible directory listing.
  final List<_PathSegment> _pathStack = [
    const _PathSegment('Root', ''),
  ];

  // Current directory items (passed from parent on push, or initial from container)
  late List<String> _currentItems;

  @override
  void initState() {
    super.initState();
    _currentItems = widget.container.rootFiles;
  }

  bool get _atRoot => _pathStack.length == 1;

  /// Push into a sub-directory.
  /// NOTE: real subdirectory listing requires the native side to support
  /// passing a path to f_opendir. For now we show a placeholder and the
  /// architecture is correct so you can wire it up later.
  void _enterDirectory(String dirName) {
    final cleanName = dirName.replaceFirst('[DIR] ', '');
    final newPath = _pathStack.last.fatPath.isEmpty
        ? cleanName
        : '${_pathStack.last.fatPath}/$cleanName';

    setState(() {
      _pathStack.add(_PathSegment(cleanName, newPath));
      // TODO: replace with real async native call:
      // final files = await CryptBridgeApi.listDirectory(widget.container, newPath);
      _currentItems = []; // placeholder — wire to native listDirectory
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Subdirectory browsing: pass "$newPath" to f_opendir'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Pop back one directory level.
  void _navigateUp() {
    if (_atRoot) return;
    setState(() {
      _pathStack.removeLast();
      // For root, restore the cached list.
      // For deeper dirs you'd cache the listing per level.
      if (_atRoot) {
        _currentItems = widget.container.rootFiles;
      } else {
        _currentItems = []; // wire to cached listings
      }
    });
  }

  Future<void> _exportFile(String fileName) async {
    final publicDownloads = Directory('/storage/emulated/0/Download');
    if (!await publicDownloads.exists()) {
      await publicDownloads.create(recursive: true);
    }
    final destPath = '${publicDownloads.path}/$fileName';

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('Exporting $fileName…')),
    );

    try {
      final success = await CryptBridgeApi.decryptFile(
        widget.container.uri,
        widget.container.password,
        widget.container.pim,
        fileName,
        destPath,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Saved to Downloads/$fileName'
              : 'Export failed'),
          backgroundColor:
              success ? const Color(0xFF1A3A2A) : null,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _showFileActions(String fileName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => _FileActionsSheet(
        fileName: fileName,
        onExport: () {
          Navigator.pop(context);
          _exportFile(fileName);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dirs =
        _currentItems.where((f) => f.startsWith('[DIR]')).toList();
    final files =
        _currentItems.where((f) => !f.startsWith('[DIR]') && !f.startsWith('System:')).toList();

    return Scaffold(
      appBar: AppBar(
        leading: _atRoot
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _navigateUp,
              ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.container.displayName,
                style: const TextStyle(fontSize: 14)),
            if (!_atRoot)
              Text(
                _pathStack.skip(1).map((s) => s.label).join(' / '),
                style: TextStyle(
                    fontSize: 11, color: cs.primary, height: 1.3),
              ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'VOL ${widget.container.volId}',
                style: TextStyle(
                  color: cs.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Breadcrumb bar
          if (_pathStack.length > 1)
            _BreadcrumbBar(
              stack: _pathStack,
              onTap: (index) {
                if (index == _pathStack.length - 1) return;
                setState(() {
                  _pathStack.removeRange(index + 1, _pathStack.length);
                  _currentItems = index == 0
                      ? widget.container.rootFiles
                      : [];
                });
              },
            ),

          // Stats bar
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: cs.surface,
            child: Row(
              children: [
                _StatChip(
                  icon: Icons.folder_outlined,
                  label: '${dirs.length} folder${dirs.length != 1 ? 's' : ''}',
                ),
                const SizedBox(width: 14),
                _StatChip(
                  icon: Icons.insert_drive_file_outlined,
                  label: '${files.length} file${files.length != 1 ? 's' : ''}',
                ),
              ],
            ),
          ),
          const Divider(),

          // File list
          Expanded(
            child: _currentItems.isEmpty && !_atRoot
                ? _DirectoryPlaceholder(onBack: _navigateUp)
                : ListView.builder(
                    itemCount: dirs.length + files.length,
                    itemBuilder: (_, index) {
                      if (index < dirs.length) {
                        return _DirectoryTile(
                          name: dirs[index].replaceFirst('[DIR] ', ''),
                          onTap: () => _enterDirectory(dirs[index]),
                        );
                      }
                      final file = files[index - dirs.length];
                      return _FileTile(
                        name: file,
                        onTap: () => _showFileActions(file),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Breadcrumb Bar
// ─────────────────────────────────────────────

class _BreadcrumbBar extends StatelessWidget {
  final List<_PathSegment> stack;
  final ValueChanged<int> onTap;
  const _BreadcrumbBar({required this.stack, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 38,
      color: cs.surface,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: stack.length,
        itemBuilder: (_, i) {
          final isLast = i == stack.length - 1;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => onTap(i),
                child: Text(
                  stack[i].label,
                  style: TextStyle(
                    color: isLast ? cs.onSurface : cs.primary,
                    fontSize: 12,
                    fontWeight:
                        isLast ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (!isLast)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.chevron_right,
                      size: 14, color: cs.outline),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Directory Tile
// ─────────────────────────────────────────────

class _DirectoryTile extends StatelessWidget {
  final String name;
  final VoidCallback onTap;
  const _DirectoryTile({required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(Icons.folder_outlined,
          size: 20, color: const Color(0xFFFFA726)),
      title: Text(name, style: Theme.of(context).textTheme.bodyMedium),
      trailing: Icon(Icons.chevron_right, size: 16, color: cs.outline),
      onTap: onTap,
    );
  }
}

// ─────────────────────────────────────────────
// File Tile
// ─────────────────────────────────────────────

class _FileTile extends StatelessWidget {
  final String name;
  final VoidCallback onTap;
  const _FileTile({required this.name, required this.onTap});

  static IconData _iconFor(String name) {
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

  static Color _colorFor(String name) {
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

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(_iconFor(name), size: 20, color: _colorFor(name)),
      title: Text(name, style: Theme.of(context).textTheme.bodyMedium),
      trailing: Icon(Icons.more_horiz,
          size: 16, color: Theme.of(context).colorScheme.outline),
      onTap: onTap,
    );
  }
}

// ─────────────────────────────────────────────
// Subdirectory placeholder
// ─────────────────────────────────────────────

class _DirectoryPlaceholder extends StatelessWidget {
  final VoidCallback onBack;
  const _DirectoryPlaceholder({required this.onBack});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open, size: 40, color: cs.outline),
          const SizedBox(height: 12),
          Text('Subdirectory browsing', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Wire listDirectory() in the native layer to pass the path to f_opendir. See the inline TODO.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Go back'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// File Actions Sheet
// ─────────────────────────────────────────────

class _FileActionsSheet extends StatelessWidget {
  final String fileName;
  final VoidCallback onExport;

  const _FileActionsSheet({
    required this.fileName,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toUpperCase()
        : 'FILE';

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // File info header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.surfaceVariant,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: cs.outline),
                  ),
                  child: Text(ext,
                      style: TextStyle(
                          color: cs.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    fileName,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),

            // Actions
            _ActionItem(
              icon: Icons.download_outlined,
              label: 'Export to Downloads',
              subtitle: 'Decrypt and save to /storage/emulated/0/Download',
              onTap: onExport,
            ),
            const SizedBox(height: 4),
            _ActionItem(
              icon: Icons.share_outlined,
              label: 'Export & Share',
              subtitle: 'Coming soon',
              onTap: null,
            ),
            const SizedBox(height: 4),
            _ActionItem(
              icon: Icons.delete_outline,
              label: 'Delete from container',
              subtitle: 'Coming soon',
              onTap: null,
              color: cs.error,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;
  final Color? color;

  const _ActionItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = color ?? cs.onSurface;
    final disabled = onTap == null;

    return ListTile(
      dense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      leading: Icon(icon,
          size: 20,
          color: disabled
              ? cs.outline
              : effectiveColor),
      title: Text(
        label,
        style: TextStyle(
          color: disabled ? cs.outline : effectiveColor,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(subtitle,
          style: TextStyle(
              color: disabled ? cs.outline.withOpacity(0.6) : cs.outline,
              fontSize: 11)),
      onTap: onTap,
    );
  }
}