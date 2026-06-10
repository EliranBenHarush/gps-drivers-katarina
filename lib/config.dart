class AppConfig {
  // Token מוגדר בעת הרצה עם: --dart-define=MAPBOX_TOKEN=pk.xxx
  static const String mapboxToken = String.fromEnvironment(
    'MAPBOX_TOKEN',
    defaultValue: '',
  );

  // PIN מנהל מוגדר בעת הרצה עם: --dart-define=ADMIN_PIN=your-pin
  static const String adminPin = String.fromEnvironment(
    'ADMIN_PIN',
    defaultValue: '',
  );

  // סגנון מפה
  static const String mapboxStyle = 'streets-v12';
}
