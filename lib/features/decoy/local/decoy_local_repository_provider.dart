// DecoyLocalRepository has no internal mutable state -- pure keep-alive
// provider per the migration plan's rule, same treatment as
// AppSettingsService/LogcatService in Phase 3.
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_local_repository.dart';

part 'decoy_local_repository_provider.g.dart';

@Riverpod(keepAlive: true)
DecoyLocalRepository decoyLocalRepository(Ref ref) =>
    const DecoyLocalRepository();
