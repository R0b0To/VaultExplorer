import 'package:test/test.dart';
import 'package:vaultexplorer/core/utils/cancellation_token.dart';

void main() {
  test('starts out not cancelled', () {
    final token = CancellationToken();
    expect(token.isCancelled, isFalse);
  });

  test('cancel() flips isCancelled', () {
    final token = CancellationToken();
    token.cancel();
    expect(token.isCancelled, isTrue);
  });

  test('cancel() invokes the bound onCancel callback', () {
    final token = CancellationToken();
    var invoked = 0;
    token.bindOnCancel(() => invoked++);
    token.cancel();
    expect(invoked, 1);
  });

  test('a second cancel() call is a no-op — onCancel fires exactly once',
      () {
    final token = CancellationToken();
    var invoked = 0;
    token.bindOnCancel(() => invoked++);
    token.cancel();
    token.cancel();
    token.cancel();
    expect(invoked, 1);
    expect(token.isCancelled, isTrue);
  });

  test('cancel() without a bound callback does not throw', () {
    final token = CancellationToken();
    expect(() => token.cancel(), returnsNormally);
  });

  test('binding a callback after the token is already cancelled does not '
      'retroactively invoke it — the callback only fires on a future '
      'cancel() call, and cancel() after cancellation is a no-op', () {
    final token = CancellationToken();
    token.cancel();
    var invoked = 0;
    token.bindOnCancel(() => invoked++);
    token.cancel(); // no-op: already cancelled
    expect(invoked, 0);
  });

  test('bindOnCancel can be called again to replace the callback before '
      'cancellation happens', () {
    final token = CancellationToken();
    var firstInvoked = 0;
    var secondInvoked = 0;
    token.bindOnCancel(() => firstInvoked++);
    token.bindOnCancel(() => secondInvoked++);
    token.cancel();
    expect(firstInvoked, 0);
    expect(secondInvoked, 1);
  });
}
