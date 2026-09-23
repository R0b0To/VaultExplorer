// Hand-written (non-codegen) Riverpod providers. The rest of this app's
// VaultXxxApi/service providers go through riverpod_generator's `@riverpod`
// (see vault_engine_providers.dart) -- this file deliberately uses plain
// `Provider(...)` instead so this feature doesn't require a `build_runner`
// regeneration pass to land. Functionally identical either way: `ref.watch`/
// `ref.read` don't care whether a provider was source-generated.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/services/password_interchange/password_interchange_service.dart';
import 'package:vaultexplorer/data/services/vault_items_service.dart';

final passwordInterchangeServiceProvider = Provider<PasswordInterchangeService>((ref) {
  return PasswordInterchangeService(
    ref.watch(vaultFileIoApiProvider),
    ref.watch(vaultItemsServiceProvider),
  );
});
