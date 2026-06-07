class AppConfig {
  // Token מוגדר בעת הרצה עם: --dart-define=MAPBOX_TOKEN=pk.xxx
  static const String mapboxToken = String.fromEnvironment(
    'MAPBOX_TOKEN',
    defaultValue: '',
  );

  // סגנון מפה
  static const String mapboxStyle = 'streets-v12';
}
