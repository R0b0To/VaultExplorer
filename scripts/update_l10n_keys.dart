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
  "galleryFilterTooltip": "Filter",
  "@galleryFilterTooltip": {
    'description': "Tooltip of the gallery filter button in the app bar",
  },
  "galleryFilterMenuOpen": "Filter…",
  "@galleryFilterMenuOpen": {
    'description': "Menu entry that opens the gallery filter sheet",
  },
  "galleryFilterClearAll": "Clear filters",
  "@galleryFilterClearAll": {
    'description': "Menu entry that removes every gallery filter",
  },
  "galleryFilterClear": "Clear",
  "@galleryFilterClear": {
    'description': "Button that removes every gallery filter (filter sheet and filter bar)",
  },
  "galleryFilterShownOfTotal": "{shown} of {total} shown",
  "@galleryFilterShownOfTotal": {
    'description': "Header of the gallery filter sheet when filters are applied: how many items are left out of the total",
    'placeholders': {
      'shown': {'type': 'int'},
      'total': {'type': 'int'},
    },
  },
  "galleryFilterTotal": "Total: {count}",
  "@galleryFilterTotal": {
    'description': "Header of the gallery filter sheet when no filter is applied: number of items",
    'placeholders': {
      'count': {'type': 'int'},
    },
  },
  "galleryFilterIndexing": "Reading photo details: {done} of {total}. Tags, places and cameras appear as it goes.",
  "@galleryFilterIndexing": {
    'description': "Progress note in the gallery filter sheet while photo metadata (EXIF, tags, GPS) is read in the background",
    'placeholders': {
      'done': {'type': 'int'},
      'total': {'type': 'int'},
    },
  },
  "galleryFilterSearchHint": "Search tags, places, cameras, folders…",
  "@galleryFilterSearchHint": {
    'description': "Hint of the search field in the gallery filter sheet",
  },
  "galleryFilterTapHint": "Tap to show only, long-press to hide.",
  "@galleryFilterTapHint": {
    'description': "Usage hint in the gallery filter sheet: tapping a chip shows only matching items, long-pressing excludes them",
  },
  "galleryFilterGroupBy": "Group by",
  "@galleryFilterGroupBy": {
    'description': "Title of the section choosing how the gallery is divided into sections",
  },
  "galleryFilterShowAll": "All {count}",
  "@galleryFilterShowAll": {
    'description': "Chip that expands a long list of filter chips; count is the total number of chips",
    'placeholders': {
      'count': {'type': 'int'},
    },
  },
  "galleryFilterShowFewer": "Fewer",
  "@galleryFilterShowFewer": {
    'description': "Chip that collapses an expanded list of filter chips",
  },
  "galleryGroupNone": "None",
  "@galleryGroupNone": {
    'description': "Gallery grouping option: no sections",
  },
  "galleryGroupDay": "Day",
  "@galleryGroupDay": {
    'description': "Gallery grouping option: one section per day",
  },
  "galleryGroupMonth": "Month",
  "@galleryGroupMonth": {
    'description': "Gallery grouping option: one section per month",
  },
  "galleryGroupYear": "Year",
  "@galleryGroupYear": {
    'description': "Gallery grouping option: one section per year",
  },
  "galleryGroupFolder": "Folder",
  "@galleryGroupFolder": {
    'description': "Gallery grouping option: one section per folder",
  },
  "galleryGroupType": "Type",
  "@galleryGroupType": {
    'description': "Gallery grouping option: one section per media type (photos, videos...)",
  },
  "galleryGroupPlace": "Place",
  "@galleryGroupPlace": {
    'description': "Gallery grouping option: one section per place (city)",
  },
  "galleryGroupCamera": "Camera",
  "@galleryGroupCamera": {
    'description': "Gallery grouping option: one section per camera model",
  },
  "galleryFilterSectionType": "Type",
  "@galleryFilterSectionType": {
    'description': "Gallery filter sheet section title: media type",
  },
  "galleryFilterSectionDate": "Date",
  "@galleryFilterSectionDate": {
    'description': "Gallery filter sheet section title: year and month",
  },
  "galleryFilterSectionTags": "Tags",
  "@galleryFilterSectionTags": {
    'description': "Gallery filter sheet section title: photo tags (keywords)",
  },
  "galleryFilterSectionPlaces": "Places",
  "@galleryFilterSectionPlaces": {
    'description': "Gallery filter sheet section title: places (cities) photos were taken in",
  },
  "galleryFilterSectionCameras": "Cameras",
  "@galleryFilterSectionCameras": {
    'description': "Gallery filter sheet section title: camera models",
  },
  "galleryFilterSectionOrientation": "Orientation",
  "@galleryFilterSectionOrientation": {
    'description': "Gallery filter sheet section title: landscape, portrait, square",
  },
  "galleryFilterSectionRating": "Rating",
  "@galleryFilterSectionRating": {
    'description': "Gallery filter sheet section title: star rating",
  },
  "galleryFilterSectionSize": "File size",
  "@galleryFilterSectionSize": {
    'description': "Gallery filter sheet section title: file size ranges",
  },
  "galleryFilterSectionFolders": "Folders",
  "@galleryFilterSectionFolders": {
    'description': "Gallery filter sheet section title: folders",
  },
  "galleryFilterSectionMissing": "Missing",
  "@galleryFilterSectionMissing": {
    'description': "Gallery filter sheet section title: items that lack some information (no location, no tags...)",
  },
  "galleryTypePhotos": "Photos",
  "@galleryTypePhotos": {
    'description': "Gallery filter: still images",
  },
  "galleryTypeVideos": "Videos",
  "@galleryTypeVideos": {
    'description': "Gallery filter: videos",
  },
  "galleryTypeAnimated": "Animated",
  "@galleryTypeAnimated": {
    'description': "Gallery filter: animated images such as GIF",
  },
  "galleryOrientationLandscape": "Landscape",
  "@galleryOrientationLandscape": {
    'description': "Gallery filter: images wider than tall",
  },
  "galleryOrientationPortrait": "Portrait",
  "@galleryOrientationPortrait": {
    'description': "Gallery filter: images taller than wide",
  },
  "galleryOrientationSquare": "Square",
  "@galleryOrientationSquare": {
    'description': "Gallery filter: images as wide as tall",
  },
  "gallerySizeSmall": "Under 1 MB",
  "@gallerySizeSmall": {
    'description': "Gallery filter: files smaller than one megabyte",
  },
  "gallerySizeMedium": "1 – 10 MB",
  "@gallerySizeMedium": {
    'description': "Gallery filter: files between one and ten megabytes",
  },
  "gallerySizeLarge": "Over 10 MB",
  "@gallerySizeLarge": {
    'description': "Gallery filter: files larger than ten megabytes",
  },
  "galleryMissingLocation": "No location",
  "@galleryMissingLocation": {
    'description': "Gallery filter and group name: photos without a GPS position",
  },
  "galleryMissingTags": "No tags",
  "@galleryMissingTags": {
    'description': "Gallery filter: photos without tags",
  },
  "galleryMissingCamera": "No camera info",
  "@galleryMissingCamera": {
    'description': "Gallery filter and group name: photos without camera information",
  },
  "galleryMissingDateTaken": "No date taken",
  "@galleryMissingDateTaken": {
    'description': "Gallery filter: photos without a capture date in their metadata",
  },
  "galleryPlaceHintCity": "Nearest city, within {km} km",
  "@galleryPlaceHintCity": {
    'description': "Tooltip of a place chip that is a city; km is the search radius",
    'placeholders': {
      'km': {'type': 'int'},
    },
  },
  "galleryPlaceHintCoordinates": "No city within {km} km: grouped by coordinates",
  "@galleryPlaceHintCoordinates": {
    'description': "Tooltip of a place chip that is raw coordinates because no city is close; km is the search radius",
    'placeholders': {
      'km': {'type': 'int'},
    },
  },
};

/// Add translations for each supported language here.
/// If a translation for a key is omitted, it falls back to the English value.
const Map<String, Map<String, String>> localizedValues = {
  'ar': {
    "galleryFilterTooltip": "تصفية",
    "galleryFilterMenuOpen": "تصفية…",
    "galleryFilterClearAll": "مسح عوامل التصفية",
    "galleryFilterClear": "مسح",
    "galleryFilterShownOfTotal": "عرض {shown} من {total}",
    "galleryFilterTotal": "الإجمالي: {count}",
    "galleryFilterIndexing": "جارٍ قراءة تفاصيل الصور: {done} من {total}. تظهر الوسوم والأماكن والكاميرات تدريجيًا.",
    "galleryFilterSearchHint": "ابحث في الوسوم والأماكن والكاميرات والمجلدات…",
    "galleryFilterTapHint": "انقر للعرض فقط، واضغط مطولًا للإخفاء.",
    "galleryFilterGroupBy": "تجميع حسب",
    "galleryFilterShowAll": "الكل ({count})",
    "galleryFilterShowFewer": "أقل",
    "galleryGroupNone": "بلا",
    "galleryGroupDay": "يوم",
    "galleryGroupMonth": "شهر",
    "galleryGroupYear": "سنة",
    "galleryGroupFolder": "مجلد",
    "galleryGroupType": "نوع",
    "galleryGroupPlace": "مكان",
    "galleryGroupCamera": "كاميرا",
    "galleryFilterSectionType": "النوع",
    "galleryFilterSectionDate": "التاريخ",
    "galleryFilterSectionTags": "الوسوم",
    "galleryFilterSectionPlaces": "الأماكن",
    "galleryFilterSectionCameras": "الكاميرات",
    "galleryFilterSectionOrientation": "الاتجاه",
    "galleryFilterSectionRating": "التقييم",
    "galleryFilterSectionSize": "حجم الملف",
    "galleryFilterSectionFolders": "المجلدات",
    "galleryFilterSectionMissing": "المفقودة",
    "galleryTypePhotos": "صور",
    "galleryTypeVideos": "فيديوهات",
    "galleryTypeAnimated": "متحركة",
    "galleryOrientationLandscape": "أفقي",
    "galleryOrientationPortrait": "عمودي",
    "galleryOrientationSquare": "مربع",
    "gallerySizeSmall": "أقل من 1 ميغابايت",
    "gallerySizeMedium": "1 – 10 ميغابايت",
    "gallerySizeLarge": "أكثر من 10 ميغابايت",
    "galleryMissingLocation": "بدون موقع",
    "galleryMissingTags": "بدون وسوم",
    "galleryMissingCamera": "بدون معلومات الكاميرا",
    "galleryMissingDateTaken": "بدون تاريخ التقاط",
    "galleryPlaceHintCity": "أقرب مدينة ضمن {km} كم",
    "galleryPlaceHintCoordinates": "لا توجد مدينة ضمن {km} كم: مجمّعة حسب الإحداثيات",
  },
  'de': {
    "galleryFilterTooltip": "Filter",
    "galleryFilterMenuOpen": "Filtern…",
    "galleryFilterClearAll": "Filter zurücksetzen",
    "galleryFilterClear": "Zurücksetzen",
    "galleryFilterShownOfTotal": "{shown} von {total} angezeigt",
    "galleryFilterTotal": "Gesamt: {count}",
    "galleryFilterIndexing": "Fotodetails werden gelesen: {done} von {total}. Tags, Orte und Kameras erscheinen nach und nach.",
    "galleryFilterSearchHint": "Tags, Orte, Kameras, Ordner suchen…",
    "galleryFilterTapHint": "Tippen: nur diese anzeigen. Lange drücken: ausblenden.",
    "galleryFilterGroupBy": "Gruppieren nach",
    "galleryFilterShowAll": "Alle {count}",
    "galleryFilterShowFewer": "Weniger",
    "galleryGroupNone": "Keine",
    "galleryGroupDay": "Tag",
    "galleryGroupMonth": "Monat",
    "galleryGroupYear": "Jahr",
    "galleryGroupFolder": "Ordner",
    "galleryGroupType": "Typ",
    "galleryGroupPlace": "Ort",
    "galleryGroupCamera": "Kamera",
    "galleryFilterSectionType": "Typ",
    "galleryFilterSectionDate": "Datum",
    "galleryFilterSectionTags": "Tags",
    "galleryFilterSectionPlaces": "Orte",
    "galleryFilterSectionCameras": "Kameras",
    "galleryFilterSectionOrientation": "Ausrichtung",
    "galleryFilterSectionRating": "Bewertung",
    "galleryFilterSectionSize": "Dateigröße",
    "galleryFilterSectionFolders": "Ordner",
    "galleryFilterSectionMissing": "Fehlend",
    "galleryTypePhotos": "Fotos",
    "galleryTypeVideos": "Videos",
    "galleryTypeAnimated": "Animiert",
    "galleryOrientationLandscape": "Querformat",
    "galleryOrientationPortrait": "Hochformat",
    "galleryOrientationSquare": "Quadratisch",
    "gallerySizeSmall": "Unter 1 MB",
    "gallerySizeMedium": "1 – 10 MB",
    "gallerySizeLarge": "Über 10 MB",
    "galleryMissingLocation": "Kein Ort",
    "galleryMissingTags": "Keine Tags",
    "galleryMissingCamera": "Keine Kamerainfo",
    "galleryMissingDateTaken": "Kein Aufnahmedatum",
    "galleryPlaceHintCity": "Nächste Stadt im Umkreis von {km} km",
    "galleryPlaceHintCoordinates": "Keine Stadt im Umkreis von {km} km: nach Koordinaten gruppiert",
  },
  'es': {
    "galleryFilterTooltip": "Filtrar",
    "galleryFilterMenuOpen": "Filtrar…",
    "galleryFilterClearAll": "Quitar filtros",
    "galleryFilterClear": "Borrar",
    "galleryFilterShownOfTotal": "{shown} de {total} mostrados",
    "galleryFilterTotal": "Total: {count}",
    "galleryFilterIndexing": "Leyendo detalles de las fotos: {done} de {total}. Las etiquetas, los lugares y las cámaras aparecen a medida que avanza.",
    "galleryFilterSearchHint": "Buscar etiquetas, lugares, cámaras, carpetas…",
    "galleryFilterTapHint": "Toca para mostrar solo esto; mantén pulsado para ocultar.",
    "galleryFilterGroupBy": "Agrupar por",
    "galleryFilterShowAll": "Todos ({count})",
    "galleryFilterShowFewer": "Menos",
    "galleryGroupNone": "Ninguno",
    "galleryGroupDay": "Día",
    "galleryGroupMonth": "Mes",
    "galleryGroupYear": "Año",
    "galleryGroupFolder": "Carpeta",
    "galleryGroupType": "Tipo",
    "galleryGroupPlace": "Lugar",
    "galleryGroupCamera": "Cámara",
    "galleryFilterSectionType": "Tipo",
    "galleryFilterSectionDate": "Fecha",
    "galleryFilterSectionTags": "Etiquetas",
    "galleryFilterSectionPlaces": "Lugares",
    "galleryFilterSectionCameras": "Cámaras",
    "galleryFilterSectionOrientation": "Orientación",
    "galleryFilterSectionRating": "Valoración",
    "galleryFilterSectionSize": "Tamaño de archivo",
    "galleryFilterSectionFolders": "Carpetas",
    "galleryFilterSectionMissing": "Faltantes",
    "galleryTypePhotos": "Fotos",
    "galleryTypeVideos": "Vídeos",
    "galleryTypeAnimated": "Animados",
    "galleryOrientationLandscape": "Horizontal",
    "galleryOrientationPortrait": "Vertical",
    "galleryOrientationSquare": "Cuadrada",
    "gallerySizeSmall": "Menos de 1 MB",
    "gallerySizeMedium": "1 – 10 MB",
    "gallerySizeLarge": "Más de 10 MB",
    "galleryMissingLocation": "Sin ubicación",
    "galleryMissingTags": "Sin etiquetas",
    "galleryMissingCamera": "Sin datos de cámara",
    "galleryMissingDateTaken": "Sin fecha de captura",
    "galleryPlaceHintCity": "Ciudad más cercana, a menos de {km} km",
    "galleryPlaceHintCoordinates": "Ninguna ciudad a menos de {km} km: agrupado por coordenadas",
  },
  'fr': {
    "galleryFilterTooltip": "Filtrer",
    "galleryFilterMenuOpen": "Filtrer…",
    "galleryFilterClearAll": "Effacer les filtres",
    "galleryFilterClear": "Effacer",
    "galleryFilterShownOfTotal": "{shown} sur {total} affichés",
    "galleryFilterTotal": "Total : {count}",
    "galleryFilterIndexing": "Lecture des détails des photos : {done} sur {total}. Les étiquettes, lieux et appareils apparaissent au fur et à mesure.",
    "galleryFilterSearchHint": "Rechercher des étiquettes, lieux, appareils, dossiers…",
    "galleryFilterTapHint": "Appuyez pour n’afficher que cela, appui long pour masquer.",
    "galleryFilterGroupBy": "Regrouper par",
    "galleryFilterShowAll": "Tout ({count})",
    "galleryFilterShowFewer": "Moins",
    "galleryGroupNone": "Aucun",
    "galleryGroupDay": "Jour",
    "galleryGroupMonth": "Mois",
    "galleryGroupYear": "Année",
    "galleryGroupFolder": "Dossier",
    "galleryGroupType": "Type",
    "galleryGroupPlace": "Lieu",
    "galleryGroupCamera": "Appareil",
    "galleryFilterSectionType": "Type",
    "galleryFilterSectionDate": "Date",
    "galleryFilterSectionTags": "Étiquettes",
    "galleryFilterSectionPlaces": "Lieux",
    "galleryFilterSectionCameras": "Appareils photo",
    "galleryFilterSectionOrientation": "Orientation",
    "galleryFilterSectionRating": "Note",
    "galleryFilterSectionSize": "Taille du fichier",
    "galleryFilterSectionFolders": "Dossiers",
    "galleryFilterSectionMissing": "Manquant",
    "galleryTypePhotos": "Photos",
    "galleryTypeVideos": "Vidéos",
    "galleryTypeAnimated": "Animés",
    "galleryOrientationLandscape": "Paysage",
    "galleryOrientationPortrait": "Portrait",
    "galleryOrientationSquare": "Carré",
    "gallerySizeSmall": "Moins de 1 Mo",
    "gallerySizeMedium": "1 – 10 Mo",
    "gallerySizeLarge": "Plus de 10 Mo",
    "galleryMissingLocation": "Sans lieu",
    "galleryMissingTags": "Sans étiquettes",
    "galleryMissingCamera": "Sans infos d’appareil",
    "galleryMissingDateTaken": "Sans date de prise de vue",
    "galleryPlaceHintCity": "Ville la plus proche, à moins de {km} km",
    "galleryPlaceHintCoordinates": "Aucune ville à moins de {km} km : regroupé par coordonnées",
  },
  'it': {
    "galleryFilterTooltip": "Filtra",
    "galleryFilterMenuOpen": "Filtra…",
    "galleryFilterClearAll": "Rimuovi filtri",
    "galleryFilterClear": "Cancella",
    "galleryFilterShownOfTotal": "{shown} di {total} mostrati",
    "galleryFilterTotal": "Totale: {count}",
    "galleryFilterIndexing": "Lettura dei dettagli delle foto: {done} di {total}. Tag, luoghi e fotocamere compaiono man mano.",
    "galleryFilterSearchHint": "Cerca tag, luoghi, fotocamere, cartelle…",
    "galleryFilterTapHint": "Tocca per mostrare solo questi, tieni premuto per nascondere.",
    "galleryFilterGroupBy": "Raggruppa per",
    "galleryFilterShowAll": "Tutti ({count})",
    "galleryFilterShowFewer": "Meno",
    "galleryGroupNone": "Nessuno",
    "galleryGroupDay": "Giorno",
    "galleryGroupMonth": "Mese",
    "galleryGroupYear": "Anno",
    "galleryGroupFolder": "Cartella",
    "galleryGroupType": "Tipo",
    "galleryGroupPlace": "Luogo",
    "galleryGroupCamera": "Fotocamera",
    "galleryFilterSectionType": "Tipo",
    "galleryFilterSectionDate": "Data",
    "galleryFilterSectionTags": "Tag",
    "galleryFilterSectionPlaces": "Luoghi",
    "galleryFilterSectionCameras": "Fotocamere",
    "galleryFilterSectionOrientation": "Orientamento",
    "galleryFilterSectionRating": "Valutazione",
    "galleryFilterSectionSize": "Dimensione file",
    "galleryFilterSectionFolders": "Cartelle",
    "galleryFilterSectionMissing": "Mancanti",
    "galleryTypePhotos": "Foto",
    "galleryTypeVideos": "Video",
    "galleryTypeAnimated": "Animate",
    "galleryOrientationLandscape": "Orizzontale",
    "galleryOrientationPortrait": "Verticale",
    "galleryOrientationSquare": "Quadrata",
    "gallerySizeSmall": "Meno di 1 MB",
    "gallerySizeMedium": "1 – 10 MB",
    "gallerySizeLarge": "Oltre 10 MB",
    "galleryMissingLocation": "Senza posizione",
    "galleryMissingTags": "Senza tag",
    "galleryMissingCamera": "Senza dati fotocamera",
    "galleryMissingDateTaken": "Senza data di scatto",
    "galleryPlaceHintCity": "Città più vicina, entro {km} km",
    "galleryPlaceHintCoordinates": "Nessuna città entro {km} km: raggruppato per coordinate",
  },
  'ja': {
    "galleryFilterTooltip": "フィルター",
    "galleryFilterMenuOpen": "フィルター…",
    "galleryFilterClearAll": "フィルターを解除",
    "galleryFilterClear": "クリア",
    "galleryFilterShownOfTotal": "{total}件中{shown}件を表示",
    "galleryFilterTotal": "合計: {count}件",
    "galleryFilterIndexing": "写真の詳細を読み込み中: {done}/{total}。タグ、場所、カメラは読み込みが進むにつれて表示されます。",
    "galleryFilterSearchHint": "タグ、場所、カメラ、フォルダーを検索…",
    "galleryFilterTapHint": "タップでそれだけを表示、長押しで除外します。",
    "galleryFilterGroupBy": "グループ化",
    "galleryFilterShowAll": "すべて（{count}）",
    "galleryFilterShowFewer": "少なく表示",
    "galleryGroupNone": "なし",
    "galleryGroupDay": "日",
    "galleryGroupMonth": "月",
    "galleryGroupYear": "年",
    "galleryGroupFolder": "フォルダー",
    "galleryGroupType": "種類",
    "galleryGroupPlace": "場所",
    "galleryGroupCamera": "カメラ",
    "galleryFilterSectionType": "種類",
    "galleryFilterSectionDate": "日付",
    "galleryFilterSectionTags": "タグ",
    "galleryFilterSectionPlaces": "場所",
    "galleryFilterSectionCameras": "カメラ",
    "galleryFilterSectionOrientation": "向き",
    "galleryFilterSectionRating": "評価",
    "galleryFilterSectionSize": "ファイルサイズ",
    "galleryFilterSectionFolders": "フォルダー",
    "galleryFilterSectionMissing": "未設定",
    "galleryTypePhotos": "写真",
    "galleryTypeVideos": "動画",
    "galleryTypeAnimated": "アニメーション",
    "galleryOrientationLandscape": "横向き",
    "galleryOrientationPortrait": "縦向き",
    "galleryOrientationSquare": "正方形",
    "gallerySizeSmall": "1 MB 未満",
    "gallerySizeMedium": "1 – 10 MB",
    "gallerySizeLarge": "10 MB 超",
    "galleryMissingLocation": "位置情報なし",
    "galleryMissingTags": "タグなし",
    "galleryMissingCamera": "カメラ情報なし",
    "galleryMissingDateTaken": "撮影日なし",
    "galleryPlaceHintCity": "最寄りの都市（{km} km 以内）",
    "galleryPlaceHintCoordinates": "{km} km 以内に都市なし: 座標でグループ化",
  },
  'ko': {
    "galleryFilterTooltip": "필터",
    "galleryFilterMenuOpen": "필터…",
    "galleryFilterClearAll": "필터 지우기",
    "galleryFilterClear": "지우기",
    "galleryFilterShownOfTotal": "{total}개 중 {shown}개 표시",
    "galleryFilterTotal": "전체: {count}개",
    "galleryFilterIndexing": "사진 정보 읽는 중: {total}개 중 {done}개. 태그, 장소, 카메라는 읽는 대로 표시됩니다.",
    "galleryFilterSearchHint": "태그, 장소, 카메라, 폴더 검색…",
    "galleryFilterTapHint": "탭하면 해당 항목만 표시하고, 길게 누르면 숨깁니다.",
    "galleryFilterGroupBy": "그룹 기준",
    "galleryFilterShowAll": "전체 ({count})",
    "galleryFilterShowFewer": "간단히",
    "galleryGroupNone": "없음",
    "galleryGroupDay": "일",
    "galleryGroupMonth": "월",
    "galleryGroupYear": "년",
    "galleryGroupFolder": "폴더",
    "galleryGroupType": "유형",
    "galleryGroupPlace": "장소",
    "galleryGroupCamera": "카메라",
    "galleryFilterSectionType": "유형",
    "galleryFilterSectionDate": "날짜",
    "galleryFilterSectionTags": "태그",
    "galleryFilterSectionPlaces": "장소",
    "galleryFilterSectionCameras": "카메라",
    "galleryFilterSectionOrientation": "방향",
    "galleryFilterSectionRating": "평점",
    "galleryFilterSectionSize": "파일 크기",
    "galleryFilterSectionFolders": "폴더",
    "galleryFilterSectionMissing": "누락",
    "galleryTypePhotos": "사진",
    "galleryTypeVideos": "동영상",
    "galleryTypeAnimated": "애니메이션",
    "galleryOrientationLandscape": "가로",
    "galleryOrientationPortrait": "세로",
    "galleryOrientationSquare": "정사각형",
    "gallerySizeSmall": "1 MB 미만",
    "gallerySizeMedium": "1 – 10 MB",
    "gallerySizeLarge": "10 MB 초과",
    "galleryMissingLocation": "위치 없음",
    "galleryMissingTags": "태그 없음",
    "galleryMissingCamera": "카메라 정보 없음",
    "galleryMissingDateTaken": "촬영 날짜 없음",
    "galleryPlaceHintCity": "가장 가까운 도시 ({km} km 이내)",
    "galleryPlaceHintCoordinates": "{km} km 이내에 도시 없음: 좌표로 그룹화",
  },
  'pt': {
    "galleryFilterTooltip": "Filtrar",
    "galleryFilterMenuOpen": "Filtrar…",
    "galleryFilterClearAll": "Limpar filtros",
    "galleryFilterClear": "Limpar",
    "galleryFilterShownOfTotal": "{shown} de {total} exibidos",
    "galleryFilterTotal": "Total: {count}",
    "galleryFilterIndexing": "Lendo detalhes das fotos: {done} de {total}. Tags, locais e câmeras aparecem à medida que avança.",
    "galleryFilterSearchHint": "Pesquisar tags, locais, câmeras, pastas…",
    "galleryFilterTapHint": "Toque para mostrar só isso; mantenha pressionado para ocultar.",
    "galleryFilterGroupBy": "Agrupar por",
    "galleryFilterShowAll": "Todos ({count})",
    "galleryFilterShowFewer": "Menos",
    "galleryGroupNone": "Nenhum",
    "galleryGroupDay": "Dia",
    "galleryGroupMonth": "Mês",
    "galleryGroupYear": "Ano",
    "galleryGroupFolder": "Pasta",
    "galleryGroupType": "Tipo",
    "galleryGroupPlace": "Local",
    "galleryGroupCamera": "Câmera",
    "galleryFilterSectionType": "Tipo",
    "galleryFilterSectionDate": "Data",
    "galleryFilterSectionTags": "Tags",
    "galleryFilterSectionPlaces": "Locais",
    "galleryFilterSectionCameras": "Câmeras",
    "galleryFilterSectionOrientation": "Orientação",
    "galleryFilterSectionRating": "Avaliação",
    "galleryFilterSectionSize": "Tamanho do arquivo",
    "galleryFilterSectionFolders": "Pastas",
    "galleryFilterSectionMissing": "Ausentes",
    "galleryTypePhotos": "Fotos",
    "galleryTypeVideos": "Vídeos",
    "galleryTypeAnimated": "Animados",
    "galleryOrientationLandscape": "Paisagem",
    "galleryOrientationPortrait": "Retrato",
    "galleryOrientationSquare": "Quadrada",
    "gallerySizeSmall": "Menos de 1 MB",
    "gallerySizeMedium": "1 – 10 MB",
    "gallerySizeLarge": "Mais de 10 MB",
    "galleryMissingLocation": "Sem local",
    "galleryMissingTags": "Sem tags",
    "galleryMissingCamera": "Sem dados da câmera",
    "galleryMissingDateTaken": "Sem data de captura",
    "galleryPlaceHintCity": "Cidade mais próxima, em até {km} km",
    "galleryPlaceHintCoordinates": "Nenhuma cidade em até {km} km: agrupado por coordenadas",
  },
  'uk': {
    "galleryFilterTooltip": "Фільтр",
    "galleryFilterMenuOpen": "Фільтр…",
    "galleryFilterClearAll": "Скинути фільтри",
    "galleryFilterClear": "Скинути",
    "galleryFilterShownOfTotal": "Показано {shown} із {total}",
    "galleryFilterTotal": "Усього: {count}",
    "galleryFilterIndexing": "Читання відомостей про фото: {done} із {total}. Теги, місця й камери з’являються поступово.",
    "galleryFilterSearchHint": "Шукати теги, місця, камери, теки…",
    "galleryFilterTapHint": "Торкніться, щоб показати лише це; утримуйте, щоб приховати.",
    "galleryFilterGroupBy": "Групувати за",
    "galleryFilterShowAll": "Усі ({count})",
    "galleryFilterShowFewer": "Менше",
    "galleryGroupNone": "Немає",
    "galleryGroupDay": "День",
    "galleryGroupMonth": "Місяць",
    "galleryGroupYear": "Рік",
    "galleryGroupFolder": "Тека",
    "galleryGroupType": "Тип",
    "galleryGroupPlace": "Місце",
    "galleryGroupCamera": "Камера",
    "galleryFilterSectionType": "Тип",
    "galleryFilterSectionDate": "Дата",
    "galleryFilterSectionTags": "Теги",
    "galleryFilterSectionPlaces": "Місця",
    "galleryFilterSectionCameras": "Камери",
    "galleryFilterSectionOrientation": "Орієнтація",
    "galleryFilterSectionRating": "Оцінка",
    "galleryFilterSectionSize": "Розмір файлу",
    "galleryFilterSectionFolders": "Теки",
    "galleryFilterSectionMissing": "Відсутнє",
    "galleryTypePhotos": "Фото",
    "galleryTypeVideos": "Відео",
    "galleryTypeAnimated": "Анімовані",
    "galleryOrientationLandscape": "Альбомна",
    "galleryOrientationPortrait": "Портретна",
    "galleryOrientationSquare": "Квадратна",
    "gallerySizeSmall": "Менше ніж 1 МБ",
    "gallerySizeMedium": "1 – 10 МБ",
    "gallerySizeLarge": "Понад 10 МБ",
    "galleryMissingLocation": "Без місця",
    "galleryMissingTags": "Без тегів",
    "galleryMissingCamera": "Без даних про камеру",
    "galleryMissingDateTaken": "Без дати зйомки",
    "galleryPlaceHintCity": "Найближче місто в межах {km} км",
    "galleryPlaceHintCoordinates": "Немає міст у межах {km} км: згруповано за координатами",
  },
  'zh': {
    "galleryFilterTooltip": "筛选",
    "galleryFilterMenuOpen": "筛选…",
    "galleryFilterClearAll": "清除筛选",
    "galleryFilterClear": "清除",
    "galleryFilterShownOfTotal": "已显示 {shown} / {total}",
    "galleryFilterTotal": "共 {count} 项",
    "galleryFilterIndexing": "正在读取照片详情：{done} / {total}。标签、地点和相机会随读取进度逐步出现。",
    "galleryFilterSearchHint": "搜索标签、地点、相机、文件夹…",
    "galleryFilterTapHint": "点按仅显示，长按排除。",
    "galleryFilterGroupBy": "分组方式",
    "galleryFilterShowAll": "全部（{count}）",
    "galleryFilterShowFewer": "收起",
    "galleryGroupNone": "无",
    "galleryGroupDay": "日",
    "galleryGroupMonth": "月",
    "galleryGroupYear": "年",
    "galleryGroupFolder": "文件夹",
    "galleryGroupType": "类型",
    "galleryGroupPlace": "地点",
    "galleryGroupCamera": "相机",
    "galleryFilterSectionType": "类型",
    "galleryFilterSectionDate": "日期",
    "galleryFilterSectionTags": "标签",
    "galleryFilterSectionPlaces": "地点",
    "galleryFilterSectionCameras": "相机",
    "galleryFilterSectionOrientation": "方向",
    "galleryFilterSectionRating": "评分",
    "galleryFilterSectionSize": "文件大小",
    "galleryFilterSectionFolders": "文件夹",
    "galleryFilterSectionMissing": "缺失",
    "galleryTypePhotos": "照片",
    "galleryTypeVideos": "视频",
    "galleryTypeAnimated": "动图",
    "galleryOrientationLandscape": "横向",
    "galleryOrientationPortrait": "纵向",
    "galleryOrientationSquare": "方形",
    "gallerySizeSmall": "小于 1 MB",
    "gallerySizeMedium": "1 – 10 MB",
    "gallerySizeLarge": "大于 10 MB",
    "galleryMissingLocation": "无位置信息",
    "galleryMissingTags": "无标签",
    "galleryMissingCamera": "无相机信息",
    "galleryMissingDateTaken": "无拍摄日期",
    "galleryPlaceHintCity": "最近的城市（{km} 公里内）",
    "galleryPlaceHintCoordinates": "{km} 公里内没有城市：按坐标分组",
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