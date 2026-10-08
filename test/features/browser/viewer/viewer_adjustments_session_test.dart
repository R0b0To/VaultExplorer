import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_session_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/models/viewer_adjustments.dart';

void main() {
  const key = 'session-adjust';
  const a = '/a.jpg';
  const b = '/b.jpg';
  const warm = ViewerAdjustments(brightness: 0.2, saturation: 1.4);
  const dark = ViewerAdjustments(gamma: 0.6);

  late ProviderContainer container;
  late MediaViewerSession notifier;
  MediaViewerSessionState read() => container.read(mediaViewerSessionProvider(key));

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    notifier = container.read(mediaViewerSessionProvider(key).notifier);
  });

  group('per-file adjustments', () {
    test('start empty and unadjusted', () {
      expect(read().adjustments, isEmpty);
      expect(read().adjustmentsFor(a).isIdentity, isTrue);
      expect(read().applyAdjustmentsToAll, isFalse);
      expect(read().compareOriginal, isFalse);
    });

    test('are kept per file', () {
      notifier.setAdjustments(a, warm);
      notifier.setAdjustments(b, dark);
      expect(read().adjustmentsFor(a), warm);
      expect(read().adjustmentsFor(b), dark);
    });

    test('setting identity removes the entry', () {
      notifier.setAdjustments(a, warm);
      notifier.setAdjustments(a, ViewerAdjustments.identity);
      expect(read().adjustments.containsKey(a), isFalse);
    });

    test('resetAdjustments clears only that file', () {
      notifier.setAdjustments(a, warm);
      notifier.setAdjustments(b, dark);
      notifier.resetAdjustments(a);
      expect(read().adjustmentsFor(a).isIdentity, isTrue);
      expect(read().adjustmentsFor(b), dark);
    });

    test('rotation is unaffected', () {
      notifier.rotateClockwise(a);
      notifier.setAdjustments(a, warm);
      notifier.resetAdjustments(a);
      expect(read().rotations[a], 1);
    });

    test('forgetFile drops adjustments, and works on empty/const maps', () {
      notifier.forgetFile(a); // must not throw on the const {} defaults
      notifier.setAdjustments(a, warm);
      notifier.forgetFile(a);
      expect(read().adjustments.containsKey(a), isFalse);
    });

    test('moveAdjustments follows a rename', () {
      notifier.setAdjustments(a, warm);
      notifier.moveAdjustments(a, b);
      expect(read().adjustments.containsKey(a), isFalse);
      expect(read().adjustmentsFor(b), warm);
    });

    test('stored map is unmodifiable', () {
      notifier.setAdjustments(a, warm);
      expect(() => read().adjustments[b] = dark, throwsUnsupportedError);
    });
  });

  group('apply to all', () {
    test('seeds the shared value from the current file', () {
      notifier.setAdjustments(a, warm);
      notifier.setApplyAdjustmentsToAll(a, true);
      expect(read().applyAdjustmentsToAll, isTrue);
      expect(read().adjustmentsFor(a), warm);
      expect(read().adjustmentsFor(b), warm);
    });

    test('edits go to the shared value and leave per-file entries alone', () {
      notifier.setAdjustments(b, dark);
      notifier.setApplyAdjustmentsToAll(a, true);
      notifier.setAdjustments(a, warm);
      expect(read().adjustmentsFor(b), warm);
      expect(read().adjustments[b], dark);
    });

    test('turning it off hands the shared value to the current file only', () {
      notifier.setAdjustments(b, dark);
      notifier.setApplyAdjustmentsToAll(a, true);
      notifier.setAdjustments(a, warm);
      notifier.setApplyAdjustmentsToAll(a, false);
      expect(read().adjustmentsFor(a), warm);
      expect(read().adjustmentsFor(b), dark);
    });

    test('turning it off with identity shared value leaves no entry', () {
      notifier.setApplyAdjustmentsToAll(a, true);
      notifier.setApplyAdjustmentsToAll(a, false);
      expect(read().adjustments, isEmpty);
    });
  });

  group('compare original', () {
    test('hides adjustments while held without changing them', () {
      notifier.setAdjustments(a, warm);
      notifier.setCompareOriginal(true);
      expect(read().effectiveAdjustmentsFor(a).isIdentity, isTrue);
      expect(read().adjustmentsFor(a), warm);
      notifier.setCompareOriginal(false);
      expect(read().effectiveAdjustmentsFor(a), warm);
    });
  });
}
