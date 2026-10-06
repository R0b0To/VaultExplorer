import 'package:flutter/services.dart';

/// Name of the one platform channel the Flutter side uses to reach the Kotlin
/// engine facade (`MainActivity` / the `handlers/` groups).
///
/// This is the only place in `lib/` where the name is spelled out;
/// `scripts/check_code_boundaries.py` (run in CI) fails the build if another
/// file repeats the literal. Tests may keep spelling it out -- they fake the
/// channel by name.
const String kVaultEngineChannelName = 'com.aeidolon.vaultexplorer/engine';

/// The channel itself, for the few places that are plain const objects with no
/// `ref` to read `vaultEngineChannelProvider` from (see
/// `scripts/check_code_boundaries.py` for the allow-list of files that may
/// reference it). Everything else should take an injected [MethodChannel] or a
/// `VaultXxxApi` from `vault_engine_providers.dart`.
const MethodChannel kVaultEngineChannel = MethodChannel(kVaultEngineChannelName);
