import 'package:test/test.dart';
import 'package:vaultexplorer/core/utils/listener_registry.dart';

void main() {
  test('notify with no listeners does nothing and does not throw', () {
    final registry = ListenerRegistry<String>();
    expect(() => registry.notify('event'), returnsNormally);
  });

  test('a registered listener receives the notified event', () {
    final registry = ListenerRegistry<String>();
    final received = <String>[];
    registry.add(received.add);

    registry.notify('hello');

    expect(received, ['hello']);
  });

  test('multiple listeners are all called, in the order they were added',
      () {
    final registry = ListenerRegistry<int>();
    final calls = <String>[];
    registry.add((e) => calls.add('first:$e'));
    registry.add((e) => calls.add('second:$e'));

    registry.notify(7);

    expect(calls, ['first:7', 'second:7']);
  });

  test('remove stops a listener from receiving future events', () {
    final registry = ListenerRegistry<String>();
    final received = <String>[];
    void listener(String e) => received.add(e);
    registry.add(listener);
    registry.notify('first');
    registry.remove(listener);
    registry.notify('second');

    expect(received, ['first']);
  });

  test('the same event is delivered independently to each listener '
      '(mutation by one does not affect another\'s view)', () {
    final registry = ListenerRegistry<List<int>>();
    final seenLengths = <int>[];
    registry.add((e) => seenLengths.add(e.length));
    registry.add((e) => e.add(99)); // mutates the shared list
    registry.add((e) => seenLengths.add(e.length));

    registry.notify([1, 2, 3]);

    // Listeners run in order, so the second recorded length reflects the
    // mutation performed by the middle listener.
    expect(seenLengths, [3, 4]);
  });

  test('a listener that removes another listener mid-dispatch does not '
      'throw a concurrent-modification error, and the removed listener '
      'still receives this dispatch (notify uses a snapshot)', () {
    final registry = ListenerRegistry<String>();
    final calls = <String>[];
    void victim(String e) => calls.add('victim:$e');
    void remover(String e) {
      calls.add('remover:$e');
      registry.remove(victim);
    }

    registry.add(remover);
    registry.add(victim);

    expect(() => registry.notify('event'), returnsNormally);
    expect(calls, ['remover:event', 'victim:event']);

    calls.clear();
    registry.notify('again');
    expect(calls, ['remover:again']); // victim really was removed
  });

  test('a listener that adds another listener mid-dispatch does not '
      'invoke the new listener until the next notify', () {
    final registry = ListenerRegistry<String>();
    final calls = <String>[];
    registry.add((e) {
      calls.add('first:$e');
      registry.add((e2) => calls.add('lateAdded:$e2'));
    });

    registry.notify('one');
    expect(calls, ['first:one']);

    registry.notify('two');
    expect(calls, ['first:one', 'first:two', 'lateAdded:two']);
  });
}
