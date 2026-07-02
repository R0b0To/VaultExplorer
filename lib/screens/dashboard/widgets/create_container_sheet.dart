import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/vaultexplorer_api.dart';
import '../../../utils/validation_utils.dart';
import '../../../theme.dart';
import '../../../widgets/common_widgets.dart';

class CreateContainerSheet extends StatefulWidget {
  const CreateContainerSheet({Key? key}) : super(key: key);

  @override
  State<CreateContainerSheet> createState() => _CreateContainerSheetState();
}

class _CreateContainerSheetState extends State<CreateContainerSheet> {
  final _nameCtrl = TextEditingController(text: 'vault.tc');
  final _sizeCtrl = TextEditingController(text: '10');
  final _passwordCtrl = TextEditingController();
  final _pimCtrl = TextEditingController();

  String _sizeUnit = 'MB';
  String _fileSystem = 'FAT'; // FAT (FAT32) or exFAT
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _sizeCtrl.dispose();
    _passwordCtrl.dispose();
    _pimCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_nameCtrl.text.isEmpty) {
      setState(() => _error = 'Container name is required');
      return;
    }
    final sizeVal = double.tryParse(_sizeCtrl.text);
    if (sizeVal == null || sizeVal <= 0) {
      setState(() => _error = 'Enter a valid size greater than 0');
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
      final multiplier = _sizeUnit == 'GB' ? 1024 * 1024 * 1024 : 1024 * 1024;
      final sizeBytes = (sizeVal * multiplier).round();

      final pim = clampPim(
        _pimCtrl.text.isEmpty ? 0 : int.tryParse(_pimCtrl.text) ?? 0,
      );

      final success = await vaultExplorerApi.createContainer(
        displayName: _nameCtrl.text,
        sizeBytes: sizeBytes,
        password: _passwordCtrl.text,
        pim: pim,
        fileSystem: _fileSystem.toLowerCase(),
      );

      if (success) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Container file created successfully.'),
            ),
          );
        }
      } else {
        setState(() => _error = 'Container creation cancelled or failed.');
      }
    } on PlatformException catch (e) {
      setState(() => _error = e.message ?? 'Unknown error occurred');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AppBottomSheet(
      child: SingleChildScrollView(
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create VeraCrypt Container',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),

              // File name
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: 'File Name',
                  prefixIcon: Icon(
                    Icons.drive_file_rename_outline_rounded,
                    size: AppIconSize.small,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Size and unit selection
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _sizeCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Container Size',
                        prefixIcon: Icon(Icons.sd_card_outlined, size: AppIconSize.small),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _sizeUnit,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: const [
                        DropdownMenuItem(value: 'MB', child: Text('MB')),
                        DropdownMenuItem(value: 'GB', child: Text('GB')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _sizeUnit = val);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Password
              TextField(
                controller: _passwordCtrl,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.key_rounded, size: AppIconSize.small),
                  // FIX: previously a hand-rolled IconButton with the same
                  // outlined icon pair used correctly here — now routed
                  // through the shared widget so it can't drift from the
                  // other password fields in the app.
                  suffixIcon: PasswordVisibilityToggle(
                    obscured: _obscure,
                    onToggle: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // PIM
              TextField(
                controller: _pimCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'PIM  (leave blank for default)',
                  prefixIcon: Icon(Icons.tune_rounded, size: AppIconSize.small),
                ),
              ),
              const SizedBox(height: 12),

              // File System selection
              DropdownButtonFormField<String>(
                initialValue: _fileSystem,
                decoration: InputDecoration(
                  labelText: 'Format File System',
                  prefixIcon: Icon(Icons.dns_rounded, size: AppIconSize.small),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'FAT',
                    child: Text('FAT (FAT32)'),
                  ),
                  DropdownMenuItem(value: 'exFAT', child: Text('exFAT')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _fileSystem = val);
                },
              ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                InlineErrorBanner(_error!),
              ],

              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loading ? null : _create,
                child: _loading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation(cs.onPrimary),
                        ),
                      )
                    : const Text('Create Container'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}