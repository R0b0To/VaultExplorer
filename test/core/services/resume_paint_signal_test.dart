import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/services/resume_paint_signal.dart';

class _RecordingVaultFileIoApi extends VaultFileIoApi {
  int notifyResumedFramePaintedCalls = 0;

  _RecordingVaultFileIoApi() : super(const MethodChannel('test'));

  @override
  Future<void> notifyResumedFramePainted() async {
    notifyResumedFramePaintedCalls++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingVaultFileIoApi fakeApi;

  setUp(() {
    fakeApi = _RecordingVaultFileIoApi();
    ResumePaintSignal.unregister();
  });

  tearDown(() {
    ResumePaintSignal.unregister();
  });

  testWidgets('ResumePaintSignal fires notifyResumedFramePainted on resume and schedules frame', (tester) async {
    ResumePaintSignal.register(fakeApi);

    expect(fakeApi.notifyResumedFramePaintedCalls, 0);

    // Transition to resumed
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    // Pump a frame so the scheduled frame and post-frame callback execute
    await tester.pump();

    expect(fakeApi.notifyResumedFramePaintedCalls, 1);
  });

  testWidgets('ResumePaintSignal ignores non-resumed lifecycle states', (tester) async {
    ResumePaintSignal.register(fakeApi);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(fakeApi.notifyResumedFramePaintedCalls, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(fakeApi.notifyResumedFramePaintedCalls, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(fakeApi.notifyResumedFramePaintedCalls, 0);
  });
}
