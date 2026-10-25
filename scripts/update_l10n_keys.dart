// tool/update_l10n_keys.dart
import 'dart:convert';
import 'dart:io';

/// Add your English keys and ARB metadata here.
/// Keys starting with '@' are metadata descriptions and are only added to app_en.arb.
///
/// Example:
///   'myKey': 'My English Value',
///   '@myKey': {
///     'description': 'Description for translators',
///   },
const Map<String, dynamic> enMetadataAndValues = {
  'skinEditStarted': "Skin editor is on. Use the floating buttons on any screen to pick a color and change it.",
  '@skinEditStarted': {'description': "Snackbar shown when the floating skin editor starts."},
  'skinEditSaved': "Skin saved",
  '@skinEditSaved': {'description': "Snackbar shown after the floating skin editor is closed and the skin was saved."},
  'skinEditPickTooltip': "Pick an element to recolor",
  '@skinEditPickTooltip': {'description': "Tooltip of the floating button that turns element picking on."},
  'skinEditPickStopTooltip': "Stop picking and use the app normally",
  '@skinEditPickStopTooltip': {'description': "Tooltip of the floating button that turns element picking off again."},
  'skinEditDoneTooltip': "Save and close the skin editor",
  '@skinEditDoneTooltip': {'description': "Tooltip of the floating button that saves the skin and closes the editor."},
  'skinEditHint': "Tap any element to change its color. Tap the eyedropper again to use the app normally.",
  '@skinEditHint': {'description': "Hint in the skin editor panel before an element was picked."},
  'skinEditLayersTitle': "Colors at this spot",
  '@skinEditLayersTitle': {'description': "Heading above the list of colors painted where the user tapped."},
  'skinEditAlsoUsedBy': "The same color is also used by",
  '@skinEditAlsoUsedBy': {'description': "Heading above other skin colors that currently have the same value as the picked one."},
  'skinEditClosest': "No exact match for this paint, so this is the closest skin color.",
  '@skinEditClosest': {'description': "Note shown when the tapped color only approximately matches a skin color."},
  'skinEditNoMatch': "This spot doesn't use a skin color directly. Choose a color from the list.",
  '@skinEditNoMatch': {'description': "Message shown when the tapped spot matches no skin color."},
  'skinEditAllColors': "All colors",
  '@skinEditAllColors': {'description': "Button that shows every editable color of the current page."},
  'skinEditBackToEditor': "Back to the color editor",
  '@skinEditBackToEditor': {'description': "Button that returns from the list of all colors to the color editor."},
  'skinEditStatusInherited': "Inherited",
  '@skinEditStatusInherited': {'description': "Status of a skin color that has no custom value and follows the shared palette or default."},
  'skinEditReset': "Reset",
  '@skinEditReset': {'description': "Button that clears a custom skin color back to its default."},
  'skinEditMoreOptions': "All colors and options",
  '@skinEditMoreOptions': {'description': "Tooltip of the button that opens the full skin customization page."},
  'skinEditCollapse': "Collapse panel",
  '@skinEditCollapse': {'description': "Tooltip of the button that collapses the floating skin editor panel."},
  'skinEditExpand': "Expand panel",
  '@skinEditExpand': {'description': "Tooltip of the button that expands the floating skin editor panel."},
  'skinEditPageColors': "Colors on {page}",
  '@skinEditPageColors': {
    'description': "Heading above the editable colors of one page, for example Colors on Files.",
    'placeholders': {
      'page': {'type': 'String'},
    },
  },
};

/// Add translations for each supported language here.
/// If a translation for a key is omitted, it falls back to the English value.
const Map<String, Map<String, String>> localizedValues = {
  'ar': {
    'skinEditStarted': "محرر المظهر قيد التشغيل. استخدم الأزرار العائمة في أي شاشة لاختيار لون وتغييره.",
    'skinEditSaved': "تم حفظ المظهر",
    'skinEditPickTooltip': "اختيار عنصر لتغيير لونه",
    'skinEditPickStopTooltip': "إيقاف الاختيار واستخدام التطبيق بشكل عادي",
    'skinEditDoneTooltip': "حفظ وإغلاق محرر المظهر",
    'skinEditHint': "المس أي عنصر لتغيير لونه. المس القطارة مرة أخرى لاستخدام التطبيق بشكل عادي.",
    'skinEditLayersTitle': "الألوان في هذا الموضع",
    'skinEditAlsoUsedBy': "اللون نفسه مستخدم أيضًا في",
    'skinEditClosest': "لا يوجد تطابق تام لهذا اللون، وهذا أقرب لون في المظهر.",
    'skinEditNoMatch': "هذا الموضع لا يستخدم لون المظهر مباشرة. اختر لونًا من القائمة.",
    'skinEditAllColors': "كل الألوان",
    'skinEditBackToEditor': "العودة إلى محرر الألوان",
    'skinEditStatusInherited': "موروث",
    'skinEditReset': "إعادة تعيين",
    'skinEditMoreOptions': "كل الألوان والخيارات",
    'skinEditCollapse': "طي اللوحة",
    'skinEditExpand': "توسيع اللوحة",
    'skinEditPageColors': "ألوان {page}",
  },
  'de': {
    'skinEditStarted': "Skin-Editor ist aktiv. Nutze die schwebenden Schaltflächen auf jedem Bildschirm, um eine Farbe auszuwählen und zu ändern.",
    'skinEditSaved': "Skin gespeichert",
    'skinEditPickTooltip': "Element zum Umfärben auswählen",
    'skinEditPickStopTooltip': "Auswahl beenden und App normal bedienen",
    'skinEditDoneTooltip': "Speichern und Skin-Editor schließen",
    'skinEditHint': "Tippe auf ein Element, um seine Farbe zu ändern. Tippe erneut auf die Pipette, um die App normal zu bedienen.",
    'skinEditLayersTitle': "Farben an dieser Stelle",
    'skinEditAlsoUsedBy': "Dieselbe Farbe wird auch verwendet von",
    'skinEditClosest': "Keine exakte Übereinstimmung für diese Farbe – das ist die ähnlichste Skin-Farbe.",
    'skinEditNoMatch': "Diese Stelle verwendet keine Skin-Farbe direkt. Wähle eine Farbe aus der Liste.",
    'skinEditAllColors': "Alle Farben",
    'skinEditBackToEditor': "Zurück zum Farbeditor",
    'skinEditStatusInherited': "Geerbt",
    'skinEditReset': "Zurücksetzen",
    'skinEditMoreOptions': "Alle Farben und Optionen",
    'skinEditCollapse': "Bereich einklappen",
    'skinEditExpand': "Bereich ausklappen",
    'skinEditPageColors': "Farben auf {page}",
  },
  'es': {
    'skinEditStarted': "El editor de aspecto está activado. Usa los botones flotantes en cualquier pantalla para elegir un color y cambiarlo.",
    'skinEditSaved': "Aspecto guardado",
    'skinEditPickTooltip': "Elegir un elemento para recolorear",
    'skinEditPickStopTooltip': "Dejar de elegir y usar la app con normalidad",
    'skinEditDoneTooltip': "Guardar y cerrar el editor de aspecto",
    'skinEditHint': "Toca cualquier elemento para cambiar su color. Vuelve a tocar el cuentagotas para usar la app con normalidad.",
    'skinEditLayersTitle': "Colores en este punto",
    'skinEditAlsoUsedBy': "El mismo color también lo usan",
    'skinEditClosest': "No hay coincidencia exacta para este color; este es el color del aspecto más cercano.",
    'skinEditNoMatch': "Este punto no usa directamente un color del aspecto. Elige un color de la lista.",
    'skinEditAllColors': "Todos los colores",
    'skinEditBackToEditor': "Volver al editor de color",
    'skinEditStatusInherited': "Heredado",
    'skinEditReset': "Restablecer",
    'skinEditMoreOptions': "Todos los colores y opciones",
    'skinEditCollapse': "Contraer panel",
    'skinEditExpand': "Expandir panel",
    'skinEditPageColors': "Colores de {page}",
  },
  'fr': {
    'skinEditStarted': "L'éditeur de thème est activé. Utilisez les boutons flottants sur n'importe quel écran pour choisir une couleur et la modifier.",
    'skinEditSaved': "Thème enregistré",
    'skinEditPickTooltip': "Choisir un élément à recolorer",
    'skinEditPickStopTooltip': "Arrêter la sélection et utiliser l'app normalement",
    'skinEditDoneTooltip': "Enregistrer et fermer l'éditeur de thème",
    'skinEditHint': "Touchez un élément pour changer sa couleur. Touchez à nouveau la pipette pour utiliser l'app normalement.",
    'skinEditLayersTitle': "Couleurs à cet endroit",
    'skinEditAlsoUsedBy': "La même couleur est aussi utilisée par",
    'skinEditClosest': "Aucune correspondance exacte pour cette couleur ; voici la couleur du thème la plus proche.",
    'skinEditNoMatch': "Cet endroit n'utilise pas directement une couleur du thème. Choisissez une couleur dans la liste.",
    'skinEditAllColors': "Toutes les couleurs",
    'skinEditBackToEditor': "Retour à l'éditeur de couleur",
    'skinEditStatusInherited': "Héritée",
    'skinEditReset': "Réinitialiser",
    'skinEditMoreOptions': "Toutes les couleurs et options",
    'skinEditCollapse': "Réduire le panneau",
    'skinEditExpand': "Développer le panneau",
    'skinEditPageColors': "Couleurs de {page}",
  },
  'it': {
    'skinEditStarted': "L'editor delle skin è attivo. Usa i pulsanti mobili in qualsiasi schermata per scegliere un colore e modificarlo.",
    'skinEditSaved': "Skin salvata",
    'skinEditPickTooltip': "Scegli un elemento da ricolorare",
    'skinEditPickStopTooltip': "Smetti di scegliere e usa l'app normalmente",
    'skinEditDoneTooltip': "Salva e chiudi l'editor delle skin",
    'skinEditHint': "Tocca un elemento per cambiarne il colore. Tocca di nuovo il contagocce per usare l'app normalmente.",
    'skinEditLayersTitle': "Colori in questo punto",
    'skinEditAlsoUsedBy': "Lo stesso colore è usato anche da",
    'skinEditClosest': "Nessuna corrispondenza esatta per questo colore; questo è il colore della skin più vicino.",
    'skinEditNoMatch': "Questo punto non usa direttamente un colore della skin. Scegli un colore dall'elenco.",
    'skinEditAllColors': "Tutti i colori",
    'skinEditBackToEditor': "Torna all'editor dei colori",
    'skinEditStatusInherited': "Ereditato",
    'skinEditReset': "Ripristina",
    'skinEditMoreOptions': "Tutti i colori e le opzioni",
    'skinEditCollapse': "Comprimi pannello",
    'skinEditExpand': "Espandi pannello",
    'skinEditPageColors': "Colori di {page}",
  },
  'ja': {
    'skinEditStarted': "スキンエディターがオンになりました。どの画面でも浮かぶボタンで色を選んで変更できます。",
    'skinEditSaved': "スキンを保存しました",
    'skinEditPickTooltip': "色を変える要素を選ぶ",
    'skinEditPickStopTooltip': "選択を終了して通常どおりアプリを操作",
    'skinEditDoneTooltip': "保存してスキンエディターを閉じる",
    'skinEditHint': "要素をタップすると色を変更できます。スポイトをもう一度タップすると通常どおり操作できます。",
    'skinEditLayersTitle': "この位置の色",
    'skinEditAlsoUsedBy': "同じ色は次でも使われています",
    'skinEditClosest': "この色と完全に一致するスキンカラーはありません。最も近い色です。",
    'skinEditNoMatch': "この位置ではスキンカラーが直接使われていません。リストから色を選んでください。",
    'skinEditAllColors': "すべての色",
    'skinEditBackToEditor': "カラーエディターに戻る",
    'skinEditStatusInherited': "継承",
    'skinEditReset': "リセット",
    'skinEditMoreOptions': "すべての色とオプション",
    'skinEditCollapse': "パネルを折りたたむ",
    'skinEditExpand': "パネルを展開",
    'skinEditPageColors': "{page}の色",
  },
  'ko': {
    'skinEditStarted': "스킨 편집기가 켜졌습니다. 어느 화면에서든 떠 있는 버튼으로 색을 골라 바꿀 수 있습니다.",
    'skinEditSaved': "스킨이 저장되었습니다",
    'skinEditPickTooltip': "색을 바꿀 요소 선택",
    'skinEditPickStopTooltip': "선택을 끄고 앱을 평소처럼 사용",
    'skinEditDoneTooltip': "저장하고 스킨 편집기 닫기",
    'skinEditHint': "요소를 탭하면 색을 바꿀 수 있습니다. 스포이트를 다시 탭하면 앱을 평소처럼 사용할 수 있습니다.",
    'skinEditLayersTitle': "이 위치의 색",
    'skinEditAlsoUsedBy': "같은 색을 함께 사용하는 항목",
    'skinEditClosest': "이 색과 정확히 일치하는 스킨 색이 없어 가장 가까운 색을 보여 줍니다.",
    'skinEditNoMatch': "이 위치는 스킨 색을 직접 사용하지 않습니다. 목록에서 색을 선택하세요.",
    'skinEditAllColors': "모든 색",
    'skinEditBackToEditor': "색 편집기로 돌아가기",
    'skinEditStatusInherited': "상속됨",
    'skinEditReset': "초기화",
    'skinEditMoreOptions': "모든 색과 옵션",
    'skinEditCollapse': "패널 접기",
    'skinEditExpand': "패널 펼치기",
    'skinEditPageColors': "{page}의 색",
  },
  'pt': {
    'skinEditStarted': "O editor de skins está ativo. Use os botões flutuantes em qualquer tela para escolher uma cor e alterá-la.",
    'skinEditSaved': "Skin salva",
    'skinEditPickTooltip': "Escolher um elemento para recolorir",
    'skinEditPickStopTooltip': "Parar de escolher e usar o app normalmente",
    'skinEditDoneTooltip': "Salvar e fechar o editor de skins",
    'skinEditHint': "Toque em qualquer elemento para mudar sua cor. Toque no conta-gotas novamente para usar o app normalmente.",
    'skinEditLayersTitle': "Cores neste ponto",
    'skinEditAlsoUsedBy': "A mesma cor também é usada por",
    'skinEditClosest': "Não há correspondência exata para esta cor; esta é a cor da skin mais próxima.",
    'skinEditNoMatch': "Este ponto não usa diretamente uma cor da skin. Escolha uma cor na lista.",
    'skinEditAllColors': "Todas as cores",
    'skinEditBackToEditor': "Voltar ao editor de cores",
    'skinEditStatusInherited': "Herdada",
    'skinEditReset': "Redefinir",
    'skinEditMoreOptions': "Todas as cores e opções",
    'skinEditCollapse': "Recolher painel",
    'skinEditExpand': "Expandir painel",
    'skinEditPageColors': "Cores de {page}",
  },
  'uk': {
    'skinEditStarted': "Редактор тем увімкнено. Використовуйте плаваючі кнопки на будь-якому екрані, щоб вибрати колір і змінити його.",
    'skinEditSaved': "Тему збережено",
    'skinEditPickTooltip': "Вибрати елемент для перефарбування",
    'skinEditPickStopTooltip': "Припинити вибір і користуватися застосунком як зазвичай",
    'skinEditDoneTooltip': "Зберегти й закрити редактор тем",
    'skinEditHint': "Торкніться будь-якого елемента, щоб змінити його колір. Торкніться піпетки ще раз, щоб користуватися застосунком як зазвичай.",
    'skinEditLayersTitle': "Кольори в цьому місці",
    'skinEditAlsoUsedBy': "Цей самий колір також використовують",
    'skinEditClosest': "Точного збігу для цього кольору немає; це найближчий колір теми.",
    'skinEditNoMatch': "У цьому місці не використовується колір теми напряму. Виберіть колір зі списку.",
    'skinEditAllColors': "Усі кольори",
    'skinEditBackToEditor': "Назад до редактора кольору",
    'skinEditStatusInherited': "Успадкований",
    'skinEditReset': "Скинути",
    'skinEditMoreOptions': "Усі кольори та параметри",
    'skinEditCollapse': "Згорнути панель",
    'skinEditExpand': "Розгорнути панель",
    'skinEditPageColors': "Кольори: {page}",
  },
  'zh': {
    'skinEditStarted': "皮肤编辑器已开启。在任意界面使用悬浮按钮即可选取并更改颜色。",
    'skinEditSaved': "皮肤已保存",
    'skinEditPickTooltip': "选取要更改颜色的元素",
    'skinEditPickStopTooltip': "停止选取，正常使用应用",
    'skinEditDoneTooltip': "保存并关闭皮肤编辑器",
    'skinEditHint': "点按任意元素即可更改其颜色。再次点按吸管可正常使用应用。",
    'skinEditLayersTitle': "此处的颜色",
    'skinEditAlsoUsedBy': "同一颜色还用于",
    'skinEditClosest': "此颜色没有完全匹配的皮肤颜色，这是最接近的一个。",
    'skinEditNoMatch': "此处没有直接使用皮肤颜色。请从列表中选择颜色。",
    'skinEditAllColors': "所有颜色",
    'skinEditBackToEditor': "返回颜色编辑器",
    'skinEditStatusInherited': "继承",
    'skinEditReset': "重置",
    'skinEditMoreOptions': "所有颜色和选项",
    'skinEditCollapse': "收起面板",
    'skinEditExpand': "展开面板",
    'skinEditPageColors': "{page}的颜色",
  },
};

void main() async {
  if (enMetadataAndValues.isEmpty) {
    print('No keys defined in "enMetadataAndValues". Nothing to update.');
    return;
  }

  final l10nDir = _findL10nDirectory();
  if (l10nDir == null) {
    stderr.writeln('Error: Could not find directory containing app_en.arb.');
    exit(1);
  }

  print('Targeting l10n directory: ${l10nDir.path}');

  // 1. Update primary language: app_en.arb
  final enFile = File('${l10nDir.path}/app_en.arb');
  if (enFile.existsSync()) {
    _updateArb(enFile, enMetadataAndValues);
    print('Updated: app_en.arb');
  } else {
    stderr.writeln('Error: Main language file app_en.arb not found in ${l10nDir.path}');
    exit(1);
  }

  // 2. Update secondary languages configured in localizedValues
  for (final lang in localizedValues.keys) {
    final file = File('${l10nDir.path}/app_$lang.arb');
    if (!file.existsSync()) {
      print('Notice: app_$lang.arb not found at ${file.path}, skipping.');
      continue;
    }

    final translations = localizedValues[lang] ?? {};
    final Map<String, dynamic> toInsert = {};

    for (final entry in enMetadataAndValues.entries) {
      if (entry.key.startsWith('@')) continue; // Metadata belongs only in app_en.arb
      toInsert[entry.key] = translations[entry.key] ?? entry.value;
    }

    _updateArb(file, toInsert);
    print('Updated: app_$lang.arb');
  }

  print('\nARB files updated successfully.');
  print('Run "flutter gen-l10n" to regenerate localization Dart bindings.');
}

Directory? _findL10nDirectory() {
  final candidates = [
    Directory('lib/l10n'),
    Directory('l10n'),
    Directory('../lib/l10n'),
  ];
  for (final dir in candidates) {
    if (dir.existsSync() && File('${dir.path}/app_en.arb').existsSync()) {
      return dir;
    }
  }
  return null;
}

void _updateArb(File file, Map<String, dynamic> newEntries) {
  final content = file.readAsStringSync();
  final Map<String, dynamic> jsonMap = json.decode(content);

  bool modified = false;
  for (final entry in newEntries.entries) {
    if (jsonMap[entry.key] != entry.value) {
      jsonMap[entry.key] = entry.value;
      modified = true;
    }
  }

  if (modified) {
    const encoder = JsonEncoder.withIndent('  ');
    file.writeAsStringSync('${encoder.convert(jsonMap)}\n');
  }
}