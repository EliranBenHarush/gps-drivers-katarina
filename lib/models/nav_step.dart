import 'package:latlong2/latlong.dart';

class NavStep {
  final String instruction;
  final double distance; // meters
  final double duration; // seconds
  final String maneuverType;
  final List<LatLng> points;

  const NavStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.maneuverType,
    required this.points,
  });

  factory NavStep.fromJson(Map<String, dynamic> json) {
    final maneuver = json['maneuver'] as Map<String, dynamic>;
    final geometry = json['geometry'] as Map<String, dynamic>;
    final coords = (geometry['coordinates'] as List)
        .map((c) => LatLng(
              (c[1] as num).toDouble(),
              (c[0] as num).toDouble(),
            ))
        .toList();

    return NavStep(
      instruction: maneuver['instruction'] as String? ?? '',
      distance: (json['distance'] as num?)?.toDouble() ?? 0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      maneuverType: maneuver['type'] as String? ?? '',
      points: coords,
    );
  }

  factory NavStep.fromOsrm(Map<String, dynamic> json) {
    final maneuver = json['maneuver'] as Map<String, dynamic>;
    final geometry = json['geometry'] as Map<String, dynamic>;
    final coords = (geometry['coordinates'] as List)
        .map((c) => LatLng(
              (c[1] as num).toDouble(),
              (c[0] as num).toDouble(),
            ))
        .toList();

    final type = maneuver['type'] as String? ?? '';
    final modifier = maneuver['modifier'] as String? ?? '';
    final name = json['name'] as String? ?? '';

    return NavStep(
      instruction: _buildHebrewInstruction(type, modifier, name),
      distance: (json['distance'] as num?)?.toDouble() ?? 0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      maneuverType: type,
      points: coords,
    );
  }

  static String _buildHebrewInstruction(String type, String modifier, String name) {
    final street = name.isNotEmpty ? ' על $name' : '';
    switch (type) {
      case 'depart': return 'התחל נסיעה$street';
      case 'arrive': return 'הגעת ליעד$street';
      case 'turn':
        switch (modifier) {
          case 'left': return 'פנה שמאלה$street';
          case 'right': return 'פנה ימינה$street';
          case 'slight left': return 'פנה קלות שמאלה$street';
          case 'slight right': return 'פנה קלות ימינה$street';
          case 'sharp left': return 'פנה חדות שמאלה$street';
          case 'sharp right': return 'פנה חדות ימינה$street';
          case 'uturn': return 'פנה פניית פרסה$street';
          default: return 'פנה$street';
        }
      case 'merge': return 'התמזג לכביש$street';
      case 'ramp':
        return modifier.contains('left') ? 'פנה שמאלה לרמפה' : 'פנה ימינה לרמפה';
      case 'fork':
        return modifier.contains('left') ? 'קח את המזלג השמאלי' : 'קח את המזלג הימני';
      case 'end of road':
        return modifier.contains('left') ? 'פנה שמאלה בסוף הדרך' : 'פנה ימינה בסוף הדרך';
      case 'continue': return 'המשך ישר$street';
      case 'roundabout':
      case 'rotary': return 'כנס לכיכר$street';
      case 'exit roundabout':
      case 'exit rotary': return 'צא מהכיכר$street';
      default: return 'המשך$street';
    }
  }

  String get distanceText {
    if (distance >= 1000) {
      return '${(distance / 1000).toStringAsFixed(1)} ק"מ';
    }
    return '${distance.toInt()} מ׳';
  }

  String get durationText {
    if (duration >= 3600) {
      final h = (duration / 3600).floor();
      final m = ((duration % 3600) / 60).floor();
      return '$h שע׳ $m דק׳';
    }
    return '${(duration / 60).floor()} דק׳';
  }
}
