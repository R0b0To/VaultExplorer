import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/data/models/custom_app_skin.dart';
import 'package:vaultexplorer/features/skin_editor/skin_edit_session.dart';
import 'package:vaultexplorer/features/skin_editor/skin_target.dart';

void main() {
  const red = Color(0xFFAA0000);
  const blue = Color(0xFF0000AA);
  const filesCard = AreaTokenTarget(SkinArea.files, SkinToken.surfaceCard);
  const toolsCard = AreaTokenTarget(SkinArea.tools, SkinToken.surfaceCard);

  late ProviderContainer container;
  late SkinEditSessionNotifier notifier;

  SkinEditSession session() => container.read(skinEditSessionProvider)!;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    notifier = container.read(skinEditSessionProvider.notifier);
    notifier.beginDraft(const CustomAppSkin());
  });

  test('there is no session until one is started', () {
    final fresh = ProviderContainer();
    addTearDown(fresh.dispose);
    expect(fresh.read(skinEditSessionProvider), isNull);
  });

  test('a session starts with picking on and nothing to undo', () {
    expect(session().picking, isTrue);
    expect(session().undoDepth, 0);
    expect(session().forcedBrightness, isNull);
  });

  test('repeated edits of one color in a drag are a single undo step', () {
    notifier.setColor(filesCard, red, dark: false);
    notifier.setColor(filesCard, blue, dark: false);
    expect(session().undoDepth, 1);
    expect(filesCard.customValue(session().draft, dark: false), blue);

    notifier.undo();
    expect(filesCard.isCustom(session().draft, dark: false), isFalse);
    expect(session().undoDepth, 0);
  });

  test('edits to different colors are separate undo steps', () {
    notifier.setColor(filesCard, red, dark: false);
    notifier.setColor(toolsCard, blue, dark: false);
    expect(session().undoDepth, 2);

    notifier.undo();
    expect(toolsCard.isCustom(session().draft, dark: false), isFalse);
    expect(filesCard.customValue(session().draft, dark: false), red);
  });

  test('undo with nothing to undo does nothing', () {
    final before = session().draft;
    notifier.undo();
    expect(identical(session().draft, before), isTrue);
  });

  test('picking can be toggled and the palette can be forced', () {
    notifier.togglePicking();
    expect(session().picking, isFalse);
    notifier.setPicking(true);
    expect(session().picking, isTrue);

    notifier.setForcedBrightness(Brightness.dark);
    expect(session().forcedBrightness, Brightness.dark);
    notifier.setForcedBrightness(null);
    expect(session().forcedBrightness, isNull);
  });
}
