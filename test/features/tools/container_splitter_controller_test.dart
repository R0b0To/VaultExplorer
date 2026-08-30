import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/widgets/container_splitter_controller.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('ContainerSplitterController Tests', () {
    test('initializes in split mode with default 8MB cloud preset', () {
      final state = container.read(containerSplitterProvider);

      expect(state.mode, SplitJoinMode.split);
      expect(state.preset, ChunkSizePreset.cloud8mb);
      expect(state.busy, isFalse);
      expect(state.error, isNull);
    });

    test('setMode and setPreset switch operational mode and chunk size', () {
      final controller = container.read(containerSplitterProvider.notifier);

      controller.setMode(SplitJoinMode.join);
      expect(container.read(containerSplitterProvider).mode, SplitJoinMode.join);

      controller.setPreset(ChunkSizePreset.fat32_2gb);
      expect(container.read(containerSplitterProvider).preset, ChunkSizePreset.fat32_2gb);

      controller.setMode(SplitJoinMode.split);
      expect(container.read(containerSplitterProvider).mode, SplitJoinMode.split);
    });
  });
}