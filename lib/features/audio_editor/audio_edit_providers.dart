import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/api/vault_audio_edit_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';

/// The audio editor's native API. A plain (non-generated) provider on
/// purpose, like the video editor's: it needs no `build_runner` step.
final vaultAudioEditApiProvider = Provider<VaultAudioEditApi>(
  (ref) => VaultAudioEditApi(ref.watch(vaultEngineChannelProvider)),
);
