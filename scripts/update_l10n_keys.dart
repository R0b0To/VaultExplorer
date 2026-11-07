// tool/update_l10n_keys.dart
import 'dart:convert';
import 'dart:io';

/// Add your English keys and ARB metadata here.
/// Keys starting with '@' are metadata descriptions and are only added to app_en.arb.
const Map<String, dynamic> enMetadataAndValues = {
  'libraryTabAlbums': 'Albums',
  '@libraryTabAlbums': {
    'description': 'Music library tab label',
  },
  'libraryTabArtists': 'Artists',
  '@libraryTabArtists': {
    'description': 'Music library tab label',
  },
  'libraryTabGenres': 'Genres',
  '@libraryTabGenres': {
    'description': 'Music library tab label',
  },
  'libraryTabTracks': 'Tracks',
  '@libraryTabTracks': {
    'description': 'Music library tab label',
  },
  'librarySearchHint': 'Search music',
  '@librarySearchHint': {
    'description': 'Hint text of the music library search field',
  },
  'libraryScanListing':
      'Looking through folders... {count, plural, =1{1 audio file so far} other{{count} audio files so far}}',
  '@libraryScanListing': {
    'description':
        'Progress text while the music library walks the vault folders; count is audio files found so far',
    'placeholders': {
      'count': {
        'type': 'num',
      },
    },
  },
  'libraryScanReading': 'Reading tags... {read} of {total}',
  '@libraryScanReading': {
    'description':
        'Progress text while the music library reads audio tags; read and total are file counts',
    'placeholders': {
      'read': {
        'type': 'int',
      },
      'total': {
        'type': 'int',
      },
    },
  },
  'libraryScanStop': 'Stop',
  '@libraryScanStop': {
    'description': 'Button that stops the music library scan',
  },
  'libraryEmptyTitle': 'No music found',
  '@libraryEmptyTitle': {
    'description':
        'Music library empty state title when the vault has no audio files',
  },
  'libraryEmptyMessage':
      'This vault has no audio files, or they are in folders that could not be read.',
  '@libraryEmptyMessage': {
    'description':
        'Music library empty state message when the vault has no audio files',
  },
  'libraryNoResults': 'Nothing matches your search',
  '@libraryNoResults': {
    'description': 'Music library message when a search has no matches',
  },
  'libraryUnknownArtist': 'Unknown artist',
  '@libraryUnknownArtist': {
    'description': 'Label for tracks with no artist tag',
  },
  'libraryUnknownAlbum': 'Unknown album',
  '@libraryUnknownAlbum': {
    'description': 'Label for tracks with no album tag or folder name',
  },
  'libraryUnknownGenre': 'Unknown genre',
  '@libraryUnknownGenre': {
    'description': 'Label for tracks with no genre tag',
  },
  'libraryVariousArtists': 'Various artists',
  '@libraryVariousArtists': {
    'description':
        'Label for an album whose tracks are by different artists',
  },
  'libraryTrackCount': '{count, plural, =1{1 track} other{{count} tracks}}',
  '@libraryTrackCount': {
    'description': 'Number of tracks',
    'placeholders': {
      'count': {
        'type': 'num',
      },
    },
  },
  'libraryAlbumCount': '{count, plural, =1{1 album} other{{count} albums}}',
  '@libraryAlbumCount': {
    'description': 'Number of albums',
    'placeholders': {
      'count': {
        'type': 'num',
      },
    },
  },
  'libraryPlayAll': 'Play',
  '@libraryPlayAll': {
    'description': 'Music library button that plays a list from the start',
  },
  'libraryShuffleAll': 'Shuffle',
  '@libraryShuffleAll': {
    'description': 'Music library button that plays a list in random order',
  },
  'libraryMenuRescan': 'Scan for changes',
  '@libraryMenuRescan': {
    'description':
        'Music library menu item that looks for new, changed and deleted files',
  },
  'libraryMenuRebuild': 'Re-read all tags',
  '@libraryMenuRebuild': {
    'description':
        'Music library menu item that re-reads the tags of every file',
  },
  'libraryMenuDeleteSaved': 'Delete saved index',
  '@libraryMenuDeleteSaved': {
    'description': 'Music library menu item that deletes the saved index',
  },
  'libraryMenuDeleteSavedDone': 'Saved index deleted',
  '@libraryMenuDeleteSavedDone': {
    'description':
        'Snackbar after the saved music library index was deleted',
  },
  'libraryIncompleteNote':
      'Some folders could not be read, so files that may have been removed are still listed.',
  '@libraryIncompleteNote': {
    'description':
        'Music library note shown when the last scan could not read every folder',
  },
  'libraryReadFailuresNote':
      '{count, plural, =1{1 file could not be read} other{{count} files could not be read}}',
  '@libraryReadFailuresNote': {
    'description':
        'Music library note: number of files whose tags could not be read',
    'placeholders': {
      'count': {
        'type': 'num',
      },
    },
  },
  'libraryArtistAlbumsHeader': 'Albums',
  '@libraryArtistAlbumsHeader': {
    'description': 'Heading above an artist\'s albums',
  },
  'libraryArtistTracksHeader': 'Tracks',
  '@libraryArtistTracksHeader': {
    'description': 'Heading above a list of tracks',
  },
  'librarySortTooltip': 'Sort',
  '@librarySortTooltip': {
    'description': 'Tooltip of the music library sort button',
  },
  'librarySortTitle': 'Title',
  '@librarySortTitle': {
    'description': 'Music library sort option',
  },
  'librarySortArtist': 'Artist',
  '@librarySortArtist': {
    'description': 'Music library sort option',
  },
  'librarySortAlbum': 'Album',
  '@librarySortAlbum': {
    'description': 'Music library sort option',
  },
  'librarySortYear': 'Year',
  '@librarySortYear': {
    'description': 'Music library sort option',
  },
  'librarySortRecentlyAdded': 'Recently added',
  '@librarySortRecentlyAdded': {
    'description': 'Music library sort option: newest files first',
  },
  'librarySortName': 'Name',
  '@librarySortName': {
    'description': 'Music library sort option for artists',
  },
  'librarySortTrackCount': 'Number of tracks',
  '@librarySortTrackCount': {
    'description': 'Music library sort option for artists',
  },
  'librarySortLength': 'Length',
  '@librarySortLength': {
    'description': 'Music library sort option: track duration',
  },
  'librarySortReverse': 'Reverse order',
  '@librarySortReverse': {
    'description':
        'Music library sort option that reverses the current order',
  },
  'musicModeAction': 'Music mode',
  '@musicModeAction': {
    'description':
        'File manager toolbar action that turns music mode on or off for this location',
  },
  'musicModeFiles': 'Files',
  '@musicModeFiles': {
    'description': 'Music mode bar: the normal file listing',
  },
  'musicModeMenuFolders': 'Music folders',
  '@musicModeMenuFolders': {
    'description':
        'Music mode menu item that changes which folders are included',
  },
  'musicModeMenuTurnOff': 'Turn off music mode',
  '@musicModeMenuTurnOff': {
    'description': 'Music mode menu item that turns the mode off',
  },
  'libraryStorageInVault': 'Index saved inside this vault',
  '@libraryStorageInVault': {
    'description': 'Music mode note: the index is stored in the vault itself',
  },
  'libraryStorageThisDevice': 'Index saved encrypted on this device',
  '@libraryStorageThisDevice': {
    'description':
        'Music mode note: the index is stored encrypted in app storage',
  },
  'musicScopeTitle': 'Music mode',
  '@musicScopeTitle': {
    'description': 'Title of the sheet where music mode folders are chosen',
  },
  'musicScopeMessage': 'Choose what music mode should include.',
  '@musicScopeMessage': {
    'description': 'Message in the music mode folders sheet',
  },
  'musicScopeAll': 'Everything in this location',
  '@musicScopeAll': {
    'description': 'Option: index the whole location',
  },
  'musicScopeAllHint':
      'Looks through every folder. Slower on large locations.',
  '@musicScopeAllHint': {
    'description': 'Hint under the whole-location option',
  },
  'musicScopeChoose': 'Only some folders',
  '@musicScopeChoose': {
    'description': 'Option: index only chosen folders',
  },
  'musicScopeAddFolder': 'Add a folder',
  '@musicScopeAddFolder': {
    'description': 'Button that opens the folder picker',
  },
  'musicScopeNoFolders': 'No folders chosen yet',
  '@musicScopeNoFolders': {
    'description':
        'Shown when only-some-folders is selected but none are chosen',
  },
  'musicScopeStart': 'Start',
  '@musicScopeStart': {
    'description':
        'Button that turns music mode on with the chosen folders',
  },
  'musicScopePickerAdd': 'Add this folder',
  '@musicScopePickerAdd': {
    'description': 'Button that adds the folder being viewed',
  },
  'musicScopePickerEmpty': 'No subfolders here',
  '@musicScopePickerEmpty': {
    'description': 'Folder picker empty state',
  },
  'musicScopePickerRoot': 'Top level',
  '@musicScopePickerRoot': {
    'description': 'Folder picker name for the root of a location',
  },
  'musicScopeRemoveFolder': 'Remove folder',
  '@musicScopeRemoveFolder': {
    'description': 'Tooltip of the button that removes a chosen folder',
  },
  'libraryArtistCount':
      '{count, plural, =1{1 artist} other{{count} artists}}',
  '@libraryArtistCount': {
    'description': 'Number of artists',
    'placeholders': {
      'count': {
        'type': 'num',
      },
    },
  },
  'libraryGenreCount': '{count, plural, =1{1 genre} other{{count} genres}}',
  '@libraryGenreCount': {
    'description': 'Number of genres',
    'placeholders': {
      'count': {
        'type': 'num',
      },
    },
  },
  'musicPlayPartialNote':
      'Playing {count, plural, =1{1 track} other{{count} tracks}} from {source}. The rest of this list is in other locations.',
  '@musicPlayPartialNote': {
    'description':
        'Shown when a mixed list is played: only the tracks in one location can play together',
    'placeholders': {
      'count': {
        'type': 'num',
      },
      'source': {
        'type': 'String',
      },
    },
  },
  'musicCoverChoose': 'Choose a cover image',
  '@musicCoverChoose': {
    'description':
        'Menu item that picks an image from the location\'s files as an album or artist cover',
  },
  'musicCoverRemove': 'Remove custom cover',
  '@musicCoverRemove': {
    'description': 'Menu item that removes a cover chosen by hand',
  },
  'musicCoverFailed': 'That image could not be used as a cover',
  '@musicCoverFailed': {
    'description':
        'Snackbar when the chosen image could not be read or decoded',
  },
  'musicMiniPrevious': 'Previous',
  '@musicMiniPrevious': {
    'description': 'Tooltip of the mini player previous-track button',
  },
  'musicMiniNext': 'Next',
  '@musicMiniNext': {
    'description': 'Tooltip of the mini player next-track button',
  },
  'musicMiniPlay': 'Play',
  '@musicMiniPlay': {
    'description': 'Tooltip of the mini player play button',
  },
  'musicMiniPause': 'Pause',
  '@musicMiniPause': {
    'description': 'Tooltip of the mini player pause button',
  },
  'musicMiniStop': 'Stop playback',
  '@musicMiniStop': {
    'description': 'Tooltip of the mini player button that stops the music',
  },
};

/// Translations for each supported language.
const Map<String, Map<String, String>> localizedValues = {
  'ar': {
    'libraryTabAlbums': 'الألبومات',
    'libraryTabArtists': 'الفنانون',
    'libraryTabGenres': 'الأنواع',
    'libraryTabTracks': 'المسارات',
    'librarySearchHint': 'البحث في الموسيقى',
    'libraryScanListing':
        'جارٍ فحص المجلدات... {count, plural, =1{ملف صوتي واحد حتى الآن} other{{count} ملفات صوتية حتى الآن}}',
    'libraryScanReading': 'جارٍ قراءة الوسوم... {read} من {total}',
    'libraryScanStop': 'إيقاف',
    'libraryEmptyTitle': 'لم يتم العثور على موسيقى',
    'libraryEmptyMessage':
        'لا تحتوي هذه الخزينة على ملفات صوتية، أو أنها موجودة في مجلدات تعذر قراءتها.',
    'libraryNoResults': 'لا توجد نتائج تطابق بحثك',
    'libraryUnknownArtist': 'فنان غير معروف',
    'libraryUnknownAlbum': 'ألبوم غير معروف',
    'libraryUnknownGenre': 'نوع غير معروف',
    'libraryVariousArtists': 'فنانون متنوعون',
    'libraryTrackCount': '{count, plural, =1{مسار واحد} other{{count} مسارات}}',
    'libraryAlbumCount': '{count, plural, =1{ألبوم واحد} other{{count} ألبومات}}',
    'libraryPlayAll': 'تشغيل',
    'libraryShuffleAll': 'خلط',
    'libraryMenuRescan': 'البحث عن تغييرات',
    'libraryMenuRebuild': 'إعادة قراءة جميع الوسوم',
    'libraryMenuDeleteSaved': 'حذف الفهرس المحفوظ',
    'libraryMenuDeleteSavedDone': 'تم حذف الفهرس المحفوظ',
    'libraryIncompleteNote':
        'تعذر قراءة بعض المجلدات، لذا لا تزال الملفات التي ربما تمت إزالتها مدرجة في القائمة.',
    'libraryReadFailuresNote':
        '{count, plural, =1{تعذر قراءة ملف واحد} other{تعذر قراءة {count} ملفات}}',
    'libraryArtistAlbumsHeader': 'الألبومات',
    'libraryArtistTracksHeader': 'المسارات',
    'librarySortTooltip': 'فرز',
    'librarySortTitle': 'العنوان',
    'librarySortArtist': 'الفنان',
    'librarySortAlbum': 'الألبوم',
    'librarySortYear': 'السنة',
    'librarySortRecentlyAdded': 'المضاف حديثاً',
    'librarySortName': 'الاسم',
    'librarySortTrackCount': 'عدد المسارات',
    'librarySortLength': 'المدة',
    'librarySortReverse': 'ترتيب عكسي',
    'musicModeAction': 'وضع الموسيقى',
    'musicModeFiles': 'الملفات',
    'musicModeMenuFolders': 'مجلدات الموسيقى',
    'musicModeMenuTurnOff': 'إيقاف وضع الموسيقى',
    'libraryStorageInVault': 'تم حفظ الفهرس داخل هذه الخزينة',
    'libraryStorageThisDevice': 'تم حفظ الفهرس مشفراً على هذا الجهاز',
    'musicScopeTitle': 'وضع الموسيقى',
    'musicScopeMessage': 'اختر ما يجب أن يتضمنه وضع الموسيقى.',
    'musicScopeAll': 'كل شيء في هذا الموقع',
    'musicScopeAllHint': 'يفحص كل المجلدات. يكون أبطأ في المواقع الكبيرة.',
    'musicScopeChoose': 'بعض المجلدات فقط',
    'musicScopeAddFolder': 'إضافة مجلد',
    'musicScopeNoFolders': 'لم يتم اختيار أي مجلدات بعد',
    'musicScopeStart': 'بدء',
    'musicScopePickerAdd': 'إضافة هذا المجلد',
    'musicScopePickerEmpty': 'لا توجد مجلدات فرعية هنا',
    'musicScopePickerRoot': 'المستوى الأعلى',
    'musicScopeRemoveFolder': 'إزالة المجلد',
    'libraryArtistCount': '{count, plural, =1{فنان واحد} other{{count} فنانين}}',
    'libraryGenreCount': '{count, plural, =1{نوع واحد} other{{count} أنواع}}',
    'musicPlayPartialNote':
        'جارٍ تشغيل {count, plural, =1{مسار واحد} other{{count} مسارات}} من {source}. بقية هذه القائمة في مواقع أخرى.',
    'musicCoverChoose': 'اختيار صورة غلاف',
    'musicCoverRemove': 'إزالة الغلاف المخصص',
    'musicCoverFailed': 'تعذر استخدام هذه الصورة كغلاف',
    'musicMiniPrevious': 'السابق',
    'musicMiniNext': 'التالي',
    'musicMiniPlay': 'تشغيل',
    'musicMiniPause': 'إيقاف مؤقت',
    'musicMiniStop': 'إيقاف التشغيل',
  },
  'de': {
    'libraryTabAlbums': 'Alben',
    'libraryTabArtists': 'Künstler',
    'libraryTabGenres': 'Genres',
    'libraryTabTracks': 'Titel',
    'librarySearchHint': 'Musik suchen',
    'libraryScanListing':
        'Ordner werden durchsucht... {count, plural, =1{bisher 1 Audiodatei} other{bisher {count} Audiodateien}}',
    'libraryScanReading': 'Tags werden gelesen... {read} von {total}',
    'libraryScanStop': 'Stopp',
    'libraryEmptyTitle': 'Keine Musik gefunden',
    'libraryEmptyMessage':
        'Dieser Tresor enthält keine Audiodateien oder sie befinden sich in Ordnern, die nicht gelesen werden konnten.',
    'libraryNoResults': 'Keine Treffer für Ihre Suche',
    'libraryUnknownArtist': 'Unbekannter Künstler',
    'libraryUnknownAlbum': 'Unbekanntes Album',
    'libraryUnknownGenre': 'Unbekanntes Genre',
    'libraryVariousArtists': 'Verschiedene Künstler',
    'libraryTrackCount': '{count, plural, =1{1 Titel} other{{count} Titel}}',
    'libraryAlbumCount': '{count, plural, =1{1 Album} other{{count} Alben}}',
    'libraryPlayAll': 'Wiedergabe',
    'libraryShuffleAll': 'Zufallswiedergabe',
    'libraryMenuRescan': 'Nach Änderungen suchen',
    'libraryMenuRebuild': 'Alle Tags neu einlesen',
    'libraryMenuDeleteSaved': 'Gespeicherten Index löschen',
    'libraryMenuDeleteSavedDone': 'Gespeicherter Index gelöscht',
    'libraryIncompleteNote':
        'Einige Ordner konnten nicht gelesen werden, daher werden möglicherweise entfernte Dateien weiterhin aufgelistet.',
    'libraryReadFailuresNote':
        '{count, plural, =1{1 Datei konnte nicht gelesen werden} other{{count} Dateien konnten nicht gelesen werden}}',
    'libraryArtistAlbumsHeader': 'Alben',
    'libraryArtistTracksHeader': 'Titel',
    'librarySortTooltip': 'Sortieren',
    'librarySortTitle': 'Titel',
    'librarySortArtist': 'Künstler',
    'librarySortAlbum': 'Album',
    'librarySortYear': 'Jahr',
    'librarySortRecentlyAdded': 'Kürzlich hinzugefügt',
    'librarySortName': 'Name',
    'librarySortTrackCount': 'Anzahl der Titel',
    'librarySortLength': 'Dauer',
    'librarySortReverse': 'Umgekehrte Reihenfolge',
    'musicModeAction': 'Musikmodus',
    'musicModeFiles': 'Dateien',
    'musicModeMenuFolders': 'Musikordner',
    'musicModeMenuTurnOff': 'Musikmodus deaktivieren',
    'libraryStorageInVault': 'Index in diesem Tresor gespeichert',
    'libraryStorageThisDevice': 'Index verschlüsselt auf diesem Gerät gespeichert',
    'musicScopeTitle': 'Musikmodus',
    'musicScopeMessage': 'Wählen Sie aus, was der Musikmodus enthalten soll.',
    'musicScopeAll': 'Alles an diesem Speicherort',
    'musicScopeAllHint':
        'Durchsucht alle Ordner. Bei großen Speicherorten langsamer.',
    'musicScopeChoose': 'Nur bestimmte Ordner',
    'musicScopeAddFolder': 'Ordner hinzufügen',
    'musicScopeNoFolders': 'Noch keine Ordner ausgewählt',
    'musicScopeStart': 'Starten',
    'musicScopePickerAdd': 'Diesen Ordner hinzufügen',
    'musicScopePickerEmpty': 'Keine Unterordner vorhanden',
    'musicScopePickerRoot': 'Oberste Ebene',
    'musicScopeRemoveFolder': 'Ordner entfernen',
    'libraryArtistCount': '{count, plural, =1{1 Künstler} other{{count} Künstler}}',
    'libraryGenreCount': '{count, plural, =1{1 Genre} other{{count} Genres}}',
    'musicPlayPartialNote':
        '{count, plural, =1{1 Titel} other{{count} Titel}} von {source} wird abgespielt. Der Rest dieser Liste befindet sich an anderen Speicherorten.',
    'musicCoverChoose': 'Coverbild auswählen',
    'musicCoverRemove': 'Benutzerdefiniertes Cover entfernen',
    'musicCoverFailed': 'Dieses Bild konnte nicht als Cover verwendet werden',
    'musicMiniPrevious': 'Vorheriger Titel',
    'musicMiniNext': 'Nächster Titel',
    'musicMiniPlay': 'Abspielen',
    'musicMiniPause': 'Pause',
    'musicMiniStop': 'Wiedergabe stoppen',
  },
  'es': {
    'libraryTabAlbums': 'Álbumes',
    'libraryTabArtists': 'Artistas',
    'libraryTabGenres': 'Géneros',
    'libraryTabTracks': 'Pistas',
    'librarySearchHint': 'Buscar música',
    'libraryScanListing':
        'Buscando en las carpetas... {count, plural, =1{1 archivo de audio hasta ahora} other{{count} archivos de audio hasta ahora}}',
    'libraryScanReading': 'Leyendo etiquetas... {read} de {total}',
    'libraryScanStop': 'Detener',
    'libraryEmptyTitle': 'No se encontró música',
    'libraryEmptyMessage':
        'Esta bóveda no tiene archivos de audio o están en carpetas que no se pudieron leer.',
    'libraryNoResults': 'No hay resultados para su búsqueda',
    'libraryUnknownArtist': 'Artista desconocido',
    'libraryUnknownAlbum': 'Álbum desconocido',
    'libraryUnknownGenre': 'Género desconocido',
    'libraryVariousArtists': 'Varios artistas',
    'libraryTrackCount': '{count, plural, =1{1 pista} other{{count} pistas}}',
    'libraryAlbumCount': '{count, plural, =1{1 álbum} other{{count} álbumes}}',
    'libraryPlayAll': 'Reproducir',
    'libraryShuffleAll': 'Aleatorio',
    'libraryMenuRescan': 'Buscar cambios',
    'libraryMenuRebuild': 'Releer todas las etiquetas',
    'libraryMenuDeleteSaved': 'Eliminar índice guardado',
    'libraryMenuDeleteSavedDone': 'Índice guardado eliminado',
    'libraryIncompleteNote':
        'No se pudieron leer algunas carpetas, por lo que los archivos que pudieron haberse eliminado aún aparecen en la lista.',
    'libraryReadFailuresNote':
        '{count, plural, =1{No se pudo leer 1 archivo} other{No se pudieron leer {count} archivos}}',
    'libraryArtistAlbumsHeader': 'Álbumes',
    'libraryArtistTracksHeader': 'Pistas',
    'librarySortTooltip': 'Ordenar',
    'librarySortTitle': 'Título',
    'librarySortArtist': 'Artista',
    'librarySortAlbum': 'Álbum',
    'librarySortYear': 'Año',
    'librarySortRecentlyAdded': 'Añadidos recientemente',
    'librarySortName': 'Nombre',
    'librarySortTrackCount': 'Número de pistas',
    'librarySortLength': 'Duración',
    'librarySortReverse': 'Orden inverso',
    'musicModeAction': 'Modo de música',
    'musicModeFiles': 'Archivos',
    'musicModeMenuFolders': 'Carpetas de música',
    'musicModeMenuTurnOff': 'Desactivar modo de música',
    'libraryStorageInVault': 'Índice guardado dentro de esta bóveda',
    'libraryStorageThisDevice':
        'Índice guardado de forma cifrada en este dispositivo',
    'musicScopeTitle': 'Modo de música',
    'musicScopeMessage': 'Elija qué debe incluir el modo de música.',
    'musicScopeAll': 'Todo en esta ubicación',
    'musicScopeAllHint':
        'Examina todas las carpetas. Es más lento en ubicaciones grandes.',
    'musicScopeChoose': 'Solo algunas carpetas',
    'musicScopeAddFolder': 'Añadir una carpeta',
    'musicScopeNoFolders': 'Aún no se han elegido carpetas',
    'musicScopeStart': 'Iniciar',
    'musicScopePickerAdd': 'Añadir esta carpeta',
    'musicScopePickerEmpty': 'No hay subcarpetas aquí',
    'musicScopePickerRoot': 'Nivel superior',
    'musicScopeRemoveFolder': 'Eliminar carpeta',
    'libraryArtistCount': '{count, plural, =1{1 artista} other{{count} artistas}}',
    'libraryGenreCount': '{count, plural, =1{1 género} other{{count} géneros}}',
    'musicPlayPartialNote':
        'Reproduciendo {count, plural, =1{1 pista} other{{count} pistas}} de {source}. El resto de esta lista está en otras ubicaciones.',
    'musicCoverChoose': 'Elegir una imagen de portada',
    'musicCoverRemove': 'Eliminar portada personalizada',
    'musicCoverFailed': 'No se pudo usar esa imagen como portada',
    'musicMiniPrevious': 'Anterior',
    'musicMiniNext': 'Siguiente',
    'musicMiniPlay': 'Reproducir',
    'musicMiniPause': 'Pausar',
    'musicMiniStop': 'Detener reproducción',
  },
  'fr': {
    'libraryTabAlbums': 'Albums',
    'libraryTabArtists': 'Artistes',
    'libraryTabGenres': 'Genres',
    'libraryTabTracks': 'Pistes',
    'librarySearchHint': 'Rechercher de la musique',
    'libraryScanListing':
        'Parcours des dossiers... {count, plural, =1{1 fichier audio jusqu\'à présent} other{{count} fichiers audio jusqu\'à présent}}',
    'libraryScanReading': 'Lecture des balises... {read} sur {total}',
    'libraryScanStop': 'Arrêter',
    'libraryEmptyTitle': 'Aucune musique trouvée',
    'libraryEmptyMessage':
        'Ce coffre ne contient aucun fichier audio, ou ils se trouvent dans des dossiers illisibles.',
    'libraryNoResults': 'Aucun résultat pour votre recherche',
    'libraryUnknownArtist': 'Artiste inconnu',
    'libraryUnknownAlbum': 'Album inconnu',
    'libraryUnknownGenre': 'Genre inconnu',
    'libraryVariousArtists': 'Artistes divers',
    'libraryTrackCount': '{count, plural, =1{1 piste} other{{count} pistes}}',
    'libraryAlbumCount': '{count, plural, =1{1 album} other{{count} albums}}',
    'libraryPlayAll': 'Lire',
    'libraryShuffleAll': 'Aléatoire',
    'libraryMenuRescan': 'Rechercher les modifications',
    'libraryMenuRebuild': 'Relire toutes les balises',
    'libraryMenuDeleteSaved': 'Supprimer l\'index enregistré',
    'libraryMenuDeleteSavedDone': 'Index enregistré supprimé',
    'libraryIncompleteNote':
        'Certains dossiers n\'ont pas pu être lus, les fichiers éventuellement supprimés sont donc toujours répertoriés.',
    'libraryReadFailuresNote':
        '{count, plural, =1{1 fichier n\'a pas pu être lu} other{{count} fichiers n\'ont pas pu être lus}}',
    'libraryArtistAlbumsHeader': 'Albums',
    'libraryArtistTracksHeader': 'Pistes',
    'librarySortTooltip': 'Trier',
    'librarySortTitle': 'Titre',
    'librarySortArtist': 'Artiste',
    'librarySortAlbum': 'Album',
    'librarySortYear': 'Année',
    'librarySortRecentlyAdded': 'Ajoutés récemment',
    'librarySortName': 'Nom',
    'librarySortTrackCount': 'Nombre de pistes',
    'librarySortLength': 'Durée',
    'librarySortReverse': 'Ordre inverse',
    'musicModeAction': 'Mode musique',
    'musicModeFiles': 'Fichiers',
    'musicModeMenuFolders': 'Dossiers de musique',
    'musicModeMenuTurnOff': 'Désactiver le mode musique',
'libraryStorageInVault': 'Index enregistré dans ce coffre',
    'libraryStorageThisDevice':
        'Index enregistré et chiffré sur cet appareil',
    'musicScopeTitle': 'Mode musique',
    'musicScopeMessage': 'Choisissez ce que le mode musique doit inclure.',
    'musicScopeAll': 'Tout dans cet emplacement',
    'musicScopeAllHint':
        'Parcourt tous les dossiers. Plus lent sur les emplacements volumineux.',
    'musicScopeChoose': 'Certains dossiers uniquement',
    'musicScopeAddFolder': 'Ajouter un dossier',
    'musicScopeNoFolders': 'Aucun dossier sélectionné pour l\'instant',
    'musicScopeStart': 'Démarrer',
    'musicScopePickerAdd': 'Ajouter ce dossier',
    'musicScopePickerEmpty': 'Aucun sous-dossier ici',
    'musicScopePickerRoot': 'Niveau supérieur',
    'musicScopeRemoveFolder': 'Supprimer le dossier',
    'libraryArtistCount':
        '{count, plural, =1{1 artiste} other{{count} artistes}}',
    'libraryGenreCount': '{count, plural, =1{1 genre} other{{count} genres}}',
    'musicPlayPartialNote':
        'Lecture de {count, plural, =1{1 piste} other{{count} pistes}} depuis {source}. Le reste de cette liste se trouve dans d\'autres emplacements.',
    'musicCoverChoose': 'Choisir une image de couverture',
    'musicCoverRemove': 'Supprimer la couverture personnalisée',
    'musicCoverFailed':
        'Impossible d\'utiliser cette image comme couverture',
    'musicMiniPrevious': 'Précédent',
    'musicMiniNext': 'Suivant',
    'musicMiniPlay': 'Lire',
    'musicMiniPause': 'Pause',
    'musicMiniStop': 'Arrêter la lecture',
  },
  'it': {
    'libraryTabAlbums': 'Album',
    'libraryTabArtists': 'Artisti',
    'libraryTabGenres': 'Generi',
    'libraryTabTracks': 'Brani',
    'librarySearchHint': 'Cerca musica',
    'libraryScanListing':
        'Scansione delle cartelle in corso... {count, plural, =1{1 file audio finora} other{{count} file audio finora}}',
    'libraryScanReading': 'Lettura tag in corso... {read} di {total}',
    'libraryScanStop': 'Interrompi',
    'libraryEmptyTitle': 'Nessun brano trovato',
    'libraryEmptyMessage':
        'Questa cassaforte non contiene file audio o si trovano in cartelle non leggibili.',
    'libraryNoResults': 'Nessun risultato corrispondente alla ricerca',
    'libraryUnknownArtist': 'Artista sconosciuto',
    'libraryUnknownAlbum': 'Album sconosciuto',
    'libraryUnknownGenre': 'Genere sconosciuto',
    'libraryVariousArtists': 'Artisti vari',
    'libraryTrackCount': '{count, plural, =1{1 brano} other{{count} brani}}',
    'libraryAlbumCount': '{count, plural, =1{1 album} other{{count} album}}',
    'libraryPlayAll': 'Riproduci',
    'libraryShuffleAll': 'Riproduzione casuale',
    'libraryMenuRescan': 'Cerca modifiche',
    'libraryMenuRebuild': 'Rileggi tutti i tag',
    'libraryMenuDeleteSaved': 'Elimina indice salvato',
    'libraryMenuDeleteSavedDone': 'Indice salvato eliminato',
    'libraryIncompleteNote':
        'Alcune cartelle non sono state lette; i file eventualmente rimossi risultano ancora elencati.',
    'libraryReadFailuresNote':
        '{count, plural, =1{Impossibile leggere 1 file} other{Impossibile leggere {count} file}}',
    'libraryArtistAlbumsHeader': 'Album',
    'libraryArtistTracksHeader': 'Brani',
    'librarySortTooltip': 'Ordina',
    'librarySortTitle': 'Titolo',
    'librarySortArtist': 'Artista',
    'librarySortAlbum': 'Album',
    'librarySortYear': 'Anno',
    'librarySortRecentlyAdded': 'Aggiunti di recente',
    'librarySortName': 'Nome',
    'librarySortTrackCount': 'Numero di brani',
    'librarySortLength': 'Durata',
    'librarySortReverse': 'Ordine inverso',
    'musicModeAction': 'Modalità musica',
    'musicModeFiles': 'File',
    'musicModeMenuFolders': 'Cartelle musicali',
    'musicModeMenuTurnOff': 'Disattiva modalità musica',
    'libraryStorageInVault': 'Indice salvato in questa cassaforte',
    'libraryStorageThisDevice':
        'Indice salvato crittografato su questo dispositivo',
    'musicScopeTitle': 'Modalità musica',
    'musicScopeMessage': 'Scegli cosa includere nella modalità musica.',
    'musicScopeAll': 'Tutto in questa posizione',
    'musicScopeAllHint':
        'Esamina tutte le cartelle. Più lento su posizioni molto ampie.',
    'musicScopeChoose': 'Solo alcune cartelle',
    'musicScopeAddFolder': 'Aggiungi una cartella',
    'musicScopeNoFolders': 'Nessuna cartella ancora selezionata',
    'musicScopeStart': 'Avvia',
    'musicScopePickerAdd': 'Aggiungi questa cartella',
    'musicScopePickerEmpty': 'Nessuna sottocartella presente',
    'musicScopePickerRoot': 'Livello principale',
    'musicScopeRemoveFolder': 'Rimuovi cartella',
    'libraryArtistCount':
        '{count, plural, =1{1 artista} other{{count} artisti}}',
    'libraryGenreCount': '{count, plural, =1{1 genere} other{{count} generi}}',
    'musicPlayPartialNote':
        'Riproduzione di {count, plural, =1{1 brano} other{{count} brani}} da {source}. Il resto della lista è in altre posizioni.',
    'musicCoverChoose': 'Scegli un\'immagine di copertina',
    'musicCoverRemove': 'Rimuovi copertina personalizzata',
    'musicCoverFailed': 'Impossibile utilizzare questa immagine come copertina',
    'musicMiniPrevious': 'Precedente',
    'musicMiniNext': 'Successivo',
    'musicMiniPlay': 'Riproduci',
    'musicMiniPause': 'Pausa',
    'musicMiniStop': 'Interrompi riproduzione',
  },
  'ja': {
    'libraryTabAlbums': 'アルバム',
    'libraryTabArtists': 'アーティスト',
    'libraryTabGenres': 'ジャンル',
    'libraryTabTracks': 'トラック',
    'librarySearchHint': '音楽を検索',
    'libraryScanListing':
        'フォルダーを確認中... {count, plural, =1{現在 1 件の音声ファイル} other{現在 {count} 件の音声ファイル}}',
    'libraryScanReading': 'タグを読み込み中... {read} / {total}',
    'libraryScanStop': '停止',
    'libraryEmptyTitle': '音楽が見つかりません',
    'libraryEmptyMessage':
        'この保管庫には音声ファイルがないか、読み取れないフォルダー内にあります。',
    'libraryNoResults': '一致する検索結果がありません',
    'libraryUnknownArtist': '不明なアーティスト',
    'libraryUnknownAlbum': '不明なアルバム',
    'libraryUnknownGenre': '不明なジャンル',
    'libraryVariousArtists': 'オムニバス',
    'libraryTrackCount': '{count, plural, =1{1 曲} other{{count} 曲}}',
    'libraryAlbumCount': '{count, plural, =1{1 枚のアルバム} other{{count} 枚のアルバム}}',
    'libraryPlayAll': '再生',
    'libraryShuffleAll': 'シャッフル',
    'libraryMenuRescan': '変更を確認',
    'libraryMenuRebuild': 'すべてのタグを再読み込み',
    'libraryMenuDeleteSaved': '保存されたインデックスを削除',
    'libraryMenuDeleteSavedDone': '保存されたインデックスを削除しました',
    'libraryIncompleteNote':
        '一部のフォルダーを読み取れなかったため、削除された可能性のあるファイルが一覧に残っています。',
    'libraryReadFailuresNote':
        '{count, plural, =1{1 件のファイルを読み取れませんでした} other{{count} 件のファイルを読み取れませんでした}}',
    'libraryArtistAlbumsHeader': 'アルバム',
    'libraryArtistTracksHeader': 'トラック',
    'librarySortTooltip': '並べ替え',
    'librarySortTitle': 'タイトル',
    'librarySortArtist': 'アーティスト',
    'librarySortAlbum': 'アルバム',
    'librarySortYear': 'リリース年',
    'librarySortRecentlyAdded': '最近追加された順',
    'librarySortName': '名前',
    'librarySortTrackCount': 'トラック数',
    'librarySortLength': '再生時間',
    'librarySortReverse': '逆順',
    'musicModeAction': 'ミュージックモード',
    'musicModeFiles': 'ファイル',
    'musicModeMenuFolders': '音楽フォルダー',
    'musicModeMenuTurnOff': 'ミュージックモードをオフにする',
    'libraryStorageInVault': 'インデックスはこの保管庫内に保存されています',
    'libraryStorageThisDevice': 'インデックスはこの端末に暗号化されて保存されています',
    'musicScopeTitle': 'ミュージックモード',
    'musicScopeMessage': 'ミュージックモードに含める対象を選択してください。',
    'musicScopeAll': 'この場所のすべて',
    'musicScopeAllHint': 'すべてのフォルダーを検索します。データ量が多い場合は時間がかかります。',
    'musicScopeChoose': '特定のフォルダーのみ',
    'musicScopeAddFolder': 'フォルダーを追加',
    'musicScopeNoFolders': '選択されたフォルダーはありません',
    'musicScopeStart': '開始',
    'musicScopePickerAdd': 'このフォルダーを追加',
    'musicScopePickerEmpty': 'サブフォルダーはありません',
    'musicScopePickerRoot': 'トップレベル',
    'musicScopeRemoveFolder': 'フォルダーを削除',
    'libraryArtistCount':
        '{count, plural, =1{1 組のアーティスト} other{{count} 組のアーティスト}}',
    'libraryGenreCount': '{count, plural, =1{1 ジャンル} other{{count} ジャンル}}',
    'musicPlayPartialNote':
        '{source} から {count, plural, =1{1 曲} other{{count} 曲}} を再生しています。このリストの残りは別の場所にあります。',
    'musicCoverChoose': 'カバー画像を選択',
    'musicCoverRemove': 'カスタムカバーを削除',
    'musicCoverFailed': 'その画像はカバーとして使用できませんでした',
    'musicMiniPrevious': '前の曲',
    'musicMiniNext': '次の曲',
    'musicMiniPlay': '再生',
    'musicMiniPause': '一時停止',
    'musicMiniStop': '再生を停止',
  },
  'ko': {
    'libraryTabAlbums': '앨범',
    'libraryTabArtists': '아티스트',
    'libraryTabGenres': '장르',
    'libraryTabTracks': '트랙',
    'librarySearchHint': '음악 검색',
    'libraryScanListing':
        '폴더 검색 중... {count, plural, =1{현재 오디오 파일 1개} other{현재 오디오 파일 {count}개}}',
    'libraryScanReading': '태그 읽는 중... {read} / {total}',
    'libraryScanStop': '중지',
    'libraryEmptyTitle': '음악을 찾을 수 없음',
    'libraryEmptyMessage':
        '이 보관소에 오디오 파일이 없거나 읽을 수 없는 폴더에 있습니다.',
    'libraryNoResults': '검색 결과가 없습니다',
    'libraryUnknownArtist': '알 수 없는 아티스트',
    'libraryUnknownAlbum': '알 수 없는 앨범',
    'libraryUnknownGenre': '알 수 없는 장르',
    'libraryVariousArtists': '다양한 아티스트',
    'libraryTrackCount': '{count, plural, =1{트랙 1개} other{트랙 {count}개}}',
    'libraryAlbumCount': '{count, plural, =1{앨범 1개} other{앨범 {count}개}}',
    'libraryPlayAll': '재생',
    'libraryShuffleAll': '셔플',
    'libraryMenuRescan': '변경 사항 확인',
    'libraryMenuRebuild': '모든 태그 다시 읽기',
    'libraryMenuDeleteSaved': '저장된 색인 삭제',
    'libraryMenuDeleteSavedDone': '저장된 색인이 삭제되었습니다',
    'libraryIncompleteNote':
        '일부 폴더를 읽지 못하여 삭제되었을 수 있는 파일이 계속 표시될 수 있습니다.',
    'libraryReadFailuresNote':
        '{count, plural, =1{파일 1개를 읽지 못했습니다} other{파일 {count}개를 읽지 못했습니다}}',
    'libraryArtistAlbumsHeader': '앨범',
    'libraryArtistTracksHeader': '트랙',
    'librarySortTooltip': '정렬',
    'librarySortTitle': '제목',
    'librarySortArtist': '아티스트',
    'librarySortAlbum': '앨범',
    'librarySortYear': '연도',
    'librarySortRecentlyAdded': '최근 추가된 항목',
    'librarySortName': '이름',
    'librarySortTrackCount': '트랙 수',
    'librarySortLength': '길이',
    'librarySortReverse': '역순 정렬',
    'musicModeAction': '음악 모드',
    'musicModeFiles': '파일',
    'musicModeMenuFolders': '음악 폴더',
    'musicModeMenuTurnOff': '음악 모드 끄기',
    'libraryStorageInVault': '색인이 이 보관소 내에 저장됨',
    'libraryStorageThisDevice': '색인이 이 기기에 암호화되어 저장됨',
    'musicScopeTitle': '음악 모드',
    'musicScopeMessage': '음악 모드에 포함할 대상을 선택하세요.',
    'musicScopeAll': '이 위치의 모든 항목',
    'musicScopeAllHint':
        '모든 폴더를 탐색합니다. 위치 규모가 크면 시간이 더 걸립니다.',
    'musicScopeChoose': '일부 폴더만 선택',
    'musicScopeAddFolder': '폴더 추가',
    'musicScopeNoFolders': '아직 선택된 폴더가 없습니다',
    'musicScopeStart': '시작',
    'musicScopePickerAdd': '이 폴더 추가',
    'musicScopePickerEmpty': '하위 폴더 없음',
    'musicScopePickerRoot': '최상위 레벨',
    'musicScopeRemoveFolder': '폴더 제거',
    'libraryArtistCount':
        '{count, plural, =1{아티스트 1명} other{아티스트 {count}명}}',
    'libraryGenreCount': '{count, plural, =1{장르 1개} other{장르 {count}개}}',
    'musicPlayPartialNote':
        '{source}에서 {count, plural, =1{트랙 1개} other{트랙 {count}개}}를 재생 중입니다. 목록의 나머지 파일은 다른 위치에 있습니다.',
    'musicCoverChoose': '커버 이미지 선택',
    'musicCoverRemove': '사용자 지정 커버 제거',
    'musicCoverFailed': '해당 이미지를 커버로 사용할 수 없습니다',
    'musicMiniPrevious': '이전',
    'musicMiniNext': '다음',
    'musicMiniPlay': '재생',
    'musicMiniPause': '일시 중지',
    'musicMiniStop': '재생 중지',
  },
  'pt': {
    'libraryTabAlbums': 'Álbuns',
    'libraryTabArtists': 'Artistas',
    'libraryTabGenres': 'Gêneros',
    'libraryTabTracks': 'Faixas',
    'librarySearchHint': 'Buscar música',
    'libraryScanListing':
        'Examinando pastas... {count, plural, =1{1 arquivo de áudio até agora} other{{count} arquivos de áudio até agora}}',
    'libraryScanReading': 'Lendo tags... {read} de {total}',
    'libraryScanStop': 'Parar',
    'libraryEmptyTitle': 'Nenhuma música encontrada',
    'libraryEmptyMessage':
        'Este cofre não possui arquivos de áudio ou eles estão em pastas que não puderam ser lidas.',
    'libraryNoResults': 'Nenhum resultado corresponde à sua pesquisa',
    'libraryUnknownArtist': 'Artista desconhecido',
    'libraryUnknownAlbum': 'Álbum desconhecido',
    'libraryUnknownGenre': 'Gênero desconhecido',
    'libraryVariousArtists': 'Vários artistas',
    'libraryTrackCount': '{count, plural, =1{1 faixa} other{{count} faixas}}',
    'libraryAlbumCount': '{count, plural, =1{1 álbum} other{{count} álbuns}}',
    'libraryPlayAll': 'Reproduzir',
    'libraryShuffleAll': 'Ordem aleatória',
    'libraryMenuRescan': 'Procurar alterações',
    'libraryMenuRebuild': 'Reler todas as tags',
    'libraryMenuDeleteSaved': 'Excluir índice salvo',
    'libraryMenuDeleteSavedDone': 'Índice salvo excluído',
    'libraryIncompleteNote':
        'Algumas pastas não puderam ser lidas; arquivos que possam ter sido removidos continuam listados.',
    'libraryReadFailuresNote':
        '{count, plural, =1{1 arquivo não pôde ser lido} other{{count} arquivos não puderam ser lidos}}',
    'libraryArtistAlbumsHeader': 'Álbuns',
    'libraryArtistTracksHeader': 'Faixas',
    'librarySortTooltip': 'Ordenar',
    'librarySortTitle': 'Título',
    'librarySortArtist': 'Artista',
    'librarySortAlbum': 'Álbum',
    'librarySortYear': 'Ano',
    'librarySortRecentlyAdded': 'Adicionados recentemente',
    'librarySortName': 'Nome',
    'librarySortTrackCount': 'Número de faixas',
    'librarySortLength': 'Duração',
    'librarySortReverse': 'Ordem inversa',
    'musicModeAction': 'Modo de música',
    'musicModeFiles': 'Arquivos',
    'musicModeMenuFolders': 'Pastas de música',
    'musicModeMenuTurnOff': 'Desativar modo de música',
    'libraryStorageInVault': 'Índice salvo dentro deste cofre',
    'libraryStorageThisDevice':
        'Índice salvo criptografado neste dispositivo',
    'musicScopeTitle': 'Modo de música',
    'musicScopeMessage': 'Escolha o que o modo de música deve incluir.',
    'musicScopeAll': 'Tudo neste local',
    'musicScopeAllHint':
        'Examina todas as pastas. Mais lento em locais com muitos arquivos.',
    'musicScopeChoose': 'Apenas algumas pastas',
    'musicScopeAddFolder': 'Adicionar uma pasta',
    'musicScopeNoFolders': 'Nenhuma pasta selecionada ainda',
    'musicScopeStart': 'Iniciar',
    'musicScopePickerAdd': 'Adicionar esta pasta',
    'musicScopePickerEmpty': 'Nenhuma subpasta aqui',
    'musicScopePickerRoot': 'Nível superior',
    'musicScopeRemoveFolder': 'Remover pasta',
    'libraryArtistCount':
        '{count, plural, =1{1 artista} other{{count} artistas}}',
    'libraryGenreCount': '{count, plural, =1{1 gênero} other{{count} gêneros}}',
    'musicPlayPartialNote':
        'Reproduzindo {count, plural, =1{1 faixa} other{{count} faixas}} de {source}. O restante desta lista está em outros locais.',
    'musicCoverChoose': 'Escolher uma imagem de capa',
    'musicCoverRemove': 'Remover capa personalizada',
    'musicCoverFailed': 'Essa imagem não pôde ser usada como capa',
    'musicMiniPrevious': 'Anterior',
    'musicMiniNext': 'Próxima',
    'musicMiniPlay': 'Reproduzir',
    'musicMiniPause': 'Pausar',
    'musicMiniStop': 'Parar reprodução',
  },
  'uk': {
    'libraryTabAlbums': 'Альбоми',
    'libraryTabArtists': 'Виконавці',
    'libraryTabGenres': 'Жанри',
    'libraryTabTracks': 'Треки',
    'librarySearchHint': 'Пошук музики',
    'libraryScanListing':
        'Перегляд папок... {count, plural, =1{наразі 1 аудіофайл} other{наразі {count} аудіофайлів}}',
    'libraryScanReading': 'Зчитування тегів... {read} із {total}',
    'libraryScanStop': 'Зупинити',
    'libraryEmptyTitle': 'Музику не знайдено',
    'libraryEmptyMessage':
        'У цьому сховищі немає аудіофайлів або вони знаходяться в папках, які не вдалося прочитати.',
    'libraryNoResults': 'Нічого не відповідає вашому запиту',
    'libraryUnknownArtist': 'Невідомий виконавець',
    'libraryUnknownAlbum': 'Невідомий альбом',
    'libraryUnknownGenre': 'Невідомий жанр',
    'libraryVariousArtists': 'Різні виконавці',
    'libraryTrackCount': '{count, plural, =1{1 трек} other{{count} треків}}',
    'libraryAlbumCount': '{count, plural, =1{1 альбом} other{{count} альбомів}}',
    'libraryPlayAll': 'Відтворити',
    'libraryShuffleAll': 'Перемішати',
    'libraryMenuRescan': 'Перевірити зміни',
    'libraryMenuRebuild': 'Перечитати всі теги',
    'libraryMenuDeleteSaved': 'Видалити збережений індекс',
    'libraryMenuDeleteSavedDone': 'Збережений індекс видалено',
    'libraryIncompleteNote':
        'Деякі папки не вдалося прочитати, тому файли, які могли бути видалені, все ще відображаються.',
    'libraryReadFailuresNote':
        '{count, plural, =1{1 файл не вдалося прочитати} other{{count} файлів не вдалося прочитати}}',
    'libraryArtistAlbumsHeader': 'Альбоми',
    'libraryArtistTracksHeader': 'Треки',
    'librarySortTooltip': 'Сортування',
    'librarySortTitle': 'Назва',
    'librarySortArtist': 'Виконавець',
    'librarySortAlbum': 'Альбом',
    'librarySortYear': 'Рік',
    'librarySortRecentlyAdded': 'Нещодавно додані',
    'librarySortName': 'Ім\'я',
    'librarySortTrackCount': 'Кількість треків',
    'librarySortLength': 'Тривалість',
    'librarySortReverse': 'Зворотний порядок',
    'musicModeAction': 'Музичний режим',
    'musicModeFiles': 'Файли',
    'musicModeMenuFolders': 'Музичні папки',
    'musicModeMenuTurnOff': 'Вимкнути музичний режим',
    'libraryStorageInVault': 'Індекс збережено всередині цього сховища',
    'libraryStorageThisDevice':
        'Індекс збережено в зашифрованому вигляді на цьому пристрої',
    'musicScopeTitle': 'Музичний режим',
    'musicScopeMessage': 'Виберіть, що має включати музичний режим.',
    'musicScopeAll': 'Усе в цьому розташуванні',
    'musicScopeAllHint':
        'Перевіряє кожну папку. Працює повільніше у великих каталогах.',
    'musicScopeChoose': 'Лише деякі папки',
    'musicScopeAddFolder': 'Додати папку',
    'musicScopeNoFolders': 'Папки ще не вибрано',
    'musicScopeStart': 'Почати',
    'musicScopePickerAdd': 'Додати цю папку',
    'musicScopePickerEmpty': 'Тут немає підпапок',
    'musicScopePickerRoot': 'Верхній рівень',
    'musicScopeRemoveFolder': 'Видалити папку',
    'libraryArtistCount':
        '{count, plural, =1{1 виконавець} other{{count} виконавців}}',
    'libraryGenreCount': '{count, plural, =1{1 жанр} other{{count} жанрів}}',
    'musicPlayPartialNote':
        'Відтворення {count, plural, =1{1 треку} other{{count} треків}} із {source}. Решта треків списку знаходиться в інших місцях.',
    'musicCoverChoose': 'Вибрати обкладинку',
    'musicCoverRemove': 'Видалити власну обкладинку',
    'musicCoverFailed':
        'Не вдалося використати це зображення як обкладинку',
    'musicMiniPrevious': 'Попередній',
    'musicMiniNext': 'Наступний',
    'musicMiniPlay': 'Відтворити',
    'musicMiniPause': 'Пауза',
    'musicMiniStop': 'Зупинити відтворення',
  },
  'zh': {
    'libraryTabAlbums': '专辑',
    'libraryTabArtists': '艺术家',
    'libraryTabGenres': '流派',
    'libraryTabTracks': '曲目',
    'librarySearchHint': '搜索音乐',
    'libraryScanListing':
        '正在扫描文件夹... {count, plural, =1{已找到 1 个音频文件} other{已找到 {count} 个音频文件}}',
    'libraryScanReading': '正在读取标签... {read} / {total}',
    'libraryScanStop': '停止',
    'libraryEmptyTitle': '未找到音乐',
    'libraryEmptyMessage': '此保管库中没有音频文件，或文件所在的文件夹无法读取。',
    'libraryNoResults': '没有与搜索匹配的结果',
    'libraryUnknownArtist': '未知艺术家',
    'libraryUnknownAlbum': '未知专辑',
    'libraryUnknownGenre': '未知流派',
    'libraryVariousArtists': '群星',
    'libraryTrackCount': '{count, plural, =1{1 首曲目} other{{count} 首曲目}}',
    'libraryAlbumCount': '{count, plural, =1{1 张专辑} other{{count} 张专辑}}',
    'libraryPlayAll': '播放',
    'libraryShuffleAll': '随机播放',
    'libraryMenuRescan': '扫描更改',
    'libraryMenuRebuild': '重新读取所有标签',
    'libraryMenuDeleteSaved': '删除已保存的索引',
    'libraryMenuDeleteSavedDone': '已删除保存的索引',
    'libraryIncompleteNote':
        '某些文件夹无法读取，因此可能已被移除的文件仍显示在列表中。',
    'libraryReadFailuresNote':
        '{count, plural, =1{1 个文件无法读取} other{{count} 个文件无法读取}}',
    'libraryArtistAlbumsHeader': '专辑',
    'libraryArtistTracksHeader': '曲目',
    'librarySortTooltip': '排序',
    'librarySortTitle': '标题',
    'librarySortArtist': '艺术家',
    'librarySortAlbum': '专辑',
    'librarySortYear': '年份',
    'librarySortRecentlyAdded': '最近添加',
    'librarySortName': '名称',
    'librarySortTrackCount': '曲目数量',
    'librarySortLength': '时长',
    'librarySortReverse': '倒序',
    'musicModeAction': '音乐模式',
    'musicModeFiles': '文件',
    'musicModeMenuFolders': '音乐文件夹',
    'musicModeMenuTurnOff': '关闭音乐模式',
    'libraryStorageInVault': '索引保存在此保管库内',
    'libraryStorageThisDevice': '索引加密保存在此设备上',
    'musicScopeTitle': '音乐模式',
    'musicScopeMessage': '选择音乐模式应包含的内容。',
    'musicScopeAll': '此位置的全部内容',
    'musicScopeAllHint': '检索所有文件夹。在大型存储位置上扫描可能较慢。',
    'musicScopeChoose': '仅部分文件夹',
    'musicScopeAddFolder': '添加文件夹',
    'musicScopeNoFolders': '尚未选择文件夹',
    'musicScopeStart': '开始',
    'musicScopePickerAdd': '添加此文件夹',
    'musicScopePickerEmpty': '此处没有子文件夹',
    'musicScopePickerRoot': '顶级目录',
    'musicScopeRemoveFolder': '移除文件夹',
    'libraryArtistCount':
        '{count, plural, =1{1 位艺术家} other{{count} 位艺术家}}',
    'libraryGenreCount': '{count, plural, =1{1 个流派} other{{count} 个流派}}',
    'musicPlayPartialNote':
        '正在播放来自 {source} 的 {count, plural, =1{1 首曲目} other{{count} 首曲目}}。此列表中的其余内容位于其他位置。',
    'musicCoverChoose': '选择封面图片',
    'musicCoverRemove': '移除自定义封面',
    'musicCoverFailed': '无法将该图片用作封面',
    'musicMiniPrevious': '上一首',
    'musicMiniNext': '下一首',
    'musicMiniPlay': '播放',
    'musicMiniPause': '暂停',
    'musicMiniStop': '停止播放',
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
    stderr.writeln(
      'Error: Main language file app_en.arb not found in ${l10nDir.path}',
    );
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