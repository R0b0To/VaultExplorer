import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_automation_api.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_hash_api.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/api/vault_local_share_api.dart';
import 'package:vaultexplorer/core/api/vault_pdf_api.dart';
import 'package:vaultexplorer/core/api/vault_repair_api.dart';
import 'package:vaultexplorer/core/api/vault_split_join_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('vault_engine_providers resolves all 10 domain APIs cleanly', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(vaultEngineChannelProvider), isA<MethodChannel>());
    expect(container.read(vaultEngineEventsProvider), isA<VaultEngineEvents>());
    expect(container.read(vaultCryptoApiProvider), isA<VaultCryptoApi>());
    expect(container.read(vaultFileIoApiProvider), isA<VaultFileIoApi>());
    expect(container.read(vaultHashApiProvider), isA<VaultHashApi>());
    expect(container.read(vaultLifecycleApiProvider), isA<VaultLifecycleApi>());
    expect(container.read(vaultPdfApiProvider), isA<VaultPdfApi>());
    expect(container.read(vaultRepairApiProvider), isA<VaultRepairApi>());
    expect(container.read(vaultSplitJoinApiProvider), isA<VaultSplitJoinApi>());
    expect(container.read(vaultAutomationApiProvider), isA<VaultAutomationApi>());
    expect(container.read(vaultLocalShareApiProvider), isA<VaultLocalShareApi>());
  });

  test('domain API providers can be overridden with mocks via ProviderContainer', () {
    const mockChannel = MethodChannel('test.mock.channel');
    final mockCrypto = VaultCryptoApi(mockChannel);

    final container = ProviderContainer(
      overrides: [
        vaultCryptoApiProvider.overrideWithValue(mockCrypto),
      ],
    );
    addTearDown(container.dispose);

    final resolved = container.read(vaultCryptoApiProvider);
    expect(resolved, same(mockCrypto));
  });
}