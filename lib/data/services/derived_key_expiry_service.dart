import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';

const _kLogTag = 'DerivedKeyExpiry';

/// Launch-time sweep for cached derived keys that outlived the lifetime the
/// user picked for their vault.
///
/// The removal itself is done -- and enforced again on every key load -- by
/// the platform layer, which needs no access to the container files to do it.
/// This service only handles the consequence the platform cannot: a vault
/// whose cached key was purged this way gets derived-key caching switched
/// off, so the "temporary" convenience the user asked for really ends instead
/// of silently starting over with a fresh key on the next unlock.
class DerivedKeyExpiryService {
  const DerivedKeyExpiryService({
    required VaultCryptoApi cryptoApi,
    required ContainerRepository repository,
  }) : _cryptoApi = cryptoApi,
       _repository = repository;

  final VaultCryptoApi _cryptoApi;
  final ContainerRepository _repository;

  /// Purges every expired cached key and returns how many vaults had
  /// derived-key caching switched off as a result.
  Future<int> purgeExpired() async {
    final purged = await _cryptoApi.purgeExpiredDerivedKeys();
    if (purged.isEmpty) return 0;
    final changed = await _repository.disableDerivedKeyCachingFor(purged);
    VeLog.i(
      _kLogTag,
      'purged ${purged.length} expired cached key(s); '
      'caching switched off for $changed vault(s)',
    );
    return changed;
  }
}
