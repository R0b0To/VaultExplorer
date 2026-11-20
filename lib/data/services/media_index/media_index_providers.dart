import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';

import 'media_index_service.dart';
import 'media_index_storage.dart';

final mediaIndexServiceProvider = Provider<MediaIndexService>((ref) {
  final service = MediaIndexService(
    storage: VaultMediaIndexStorage(ref.watch(vaultFileIoApiProvider)),
    onWarning: (message, error) => VeLog.w('MediaIndex', message, error),
  );
  MediaIndexService.current = service;
  ref.onDispose(() {
    if (identical(MediaIndexService.current, service)) {
      MediaIndexService.current = null;
    }
    service.dispose();
  });
  return service;
});
