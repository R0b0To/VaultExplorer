import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';

import 'metadata_edit_service.dart';

/// The service behind the "edit tags", "edit date & time" and "remove
/// metadata" actions.
final metadataEditServiceProvider = Provider<MetadataEditService>(
  (ref) => MetadataEditService(ref.watch(vaultFileIoApiProvider)),
);
