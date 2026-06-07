import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/driver.dart';
import '../models/route_stop.dart';

class FirestoreService {
  static final _db = FirebaseFirestore.instance;

  // ─── נהגים ───────────────────────────────────────────────────────────────

  static Stream<List<Driver>> watchDrivers() {
    return _db.collection('drivers').orderBy('name').snapshots().map(
          (snap) => snap.docs
              .map((d) => Driver.fromFirestore(d.data(), d.id))
              .toList(),
        );
  }

  static Future<void> addDriver(String name, String pin) {
    return _db.collection('drivers').add({'name': name.trim(), 'pin': pin.trim()});
  }

  static Future<void> deleteDriver(String driverId) async {
    await _db.collection('drivers').doc(driverId).delete();
    await _db.collection('routes').doc(driverId).delete();
  }

  // ─── מסלולים ─────────────────────────────────────────────────────────────

  static Future<void> saveRoute(String driverId, List<RouteStop> stops) {
    return _db.collection('routes').doc(driverId).set({
      'stops': stops.map((s) => s.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<List<RouteStop>> watchRoute(String driverId) {
    return _db.collection('routes').doc(driverId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return <RouteStop>[];
      final list = (doc.data()!['stops'] as List? ?? [])
          .map((s) => RouteStop.fromMap(s as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      return list;
    });
  }

  static Future<void> clearRoute(String driverId) {
    return _db.collection('routes').doc(driverId).delete();
  }

  // ─── גבייות ──────────────────────────────────────────────────────────────

  static Future<void> saveCompletedStop({
    required String driverId,
    required String driverName,
    required String address,
    required String expectedBalance,
    required String collectedAmount,
    required String paymentMethod,
    String accountNumber = '',
  }) {
    return _db.collection('completedStops').add({
      'driverId': driverId,
      'driverName': driverName,
      'address': address,
      'expectedBalance': expectedBalance,
      'collectedAmount': collectedAmount,
      'paymentMethod': paymentMethod,
      'accountNumber': accountNumber,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> updateCompletedStop({
    required String docId,
    required String collectedAmount,
    required String paymentMethod,
  }) {
    return _db.collection('completedStops').doc(docId).update({
      'collectedAmount': collectedAmount,
      'paymentMethod': paymentMethod,
    });
  }

  static Future<void> deleteCompletedStop(String docId) {
    return _db.collection('completedStops').doc(docId).delete();
  }

  static Future<void> clearCompletedStops(String driverId) async {
    final snap = await _db
        .collection('completedStops')
        .where('driverId', isEqualTo: driverId)
        .get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  static Stream<List<Map<String, dynamic>>> watchCompletedStops(String driverId) {
    return _db
        .collection('completedStops')
        .where('driverId', isEqualTo: driverId)
        .snapshots()
        .map((snap) {
          final docs = snap.docs
              .map((d) => <String, dynamic>{...d.data(), 'docId': d.id})
              .toList();
          docs.sort((a, b) {
            final ta = a['timestamp'];
            final tb = b['timestamp'];
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return (tb as Timestamp).compareTo(ta as Timestamp);
          });
          return docs;
        });
  }
}
