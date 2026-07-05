import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vaultexplorer/main.dart';
import '../../theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About VaultExplorer'),
      ),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          _AboutCard(
            cs: cs,
            children: [
              _InfoRow('Version', appVersion, cs),
              const Divider(),
              _InfoRow('Encryption', 'AES-256-XTS (VeraCrypt)', cs),
              const Divider(),
              _InfoRow('Key derivation', 'PBKDF2-SHA512', cs),
              const Divider(),
              _InfoRow('Filesystem', 'FAT32 / exFAT via FatFs', cs),
              const Divider(),
              GestureDetector(
                onTap: () => launchUrl(
                  Uri.parse('https://github.com/R0b0To/VaultExplorer'),
                ),
                child: _InfoRow(
                  'GitHub',
                  'https://github.com/R0b0To/VaultExplorer',
                  cs,
                ),
              ),
              const Divider(),
              GestureDetector(
                onTap: () => launchUrl(
                  Uri.parse('https://ko-fi.com/r0b0to'),
                ),
                child: _InfoRow(
                  'Donate',
                  'https://ko-fi.com/r0b0to',
                  cs,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets specifically for AboutScreen ──────────────────────────────────

class _AboutCard extends StatelessWidget {
  final List<Widget> children;
  final ColorScheme cs;
  const _AboutCard({required this.children, required this.cs});

  @override
  Widget build(BuildContext context) => Card(
    color: cs.surfaceContainerLow,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;
  const _InfoRow(this.label, this.value, this.cs);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(
            label,
            style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const Spacer(),
          Text(
            value,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}