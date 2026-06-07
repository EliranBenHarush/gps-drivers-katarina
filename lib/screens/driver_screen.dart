import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../config.dart';
import '../models/driver.dart';
import '../models/route_stop.dart';
import '../models/nav_step.dart';
import '../services/firestore_service.dart';
import '../services/mapbox_service.dart';

class DriverScreen extends StatefulWidget {
  final Driver driver;
  const DriverScreen({super.key, required this.driver});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  final _mapController = MapController();

  List<RouteStop> _allStops = [];
  List<RouteStop> _stops = []; // today's stops only

  static String _todayStr() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
  List<LatLng> _routePoints = [];
  List<NavStep> _navSteps = [];
  int _currentStep = 0;
  String _totalDistance = '';
  String _totalDuration = '';

  LatLng? _userPos;
  StreamSubscription<Position>? _posSub;
  StreamSubscription<List<RouteStop>>? _routeSub;

  bool _loadingRoute = false;
  bool _navStarted = false;
  bool _mapReady = false;

  static const _defaultCenter = LatLng(32.0853, 34.7818); // תל אביב

  @override
  void initState() {
    super.initState();
    _listenRoute();
    _initLocation();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _routeSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // ─── Firebase ──────────────────────────────────────────────────────────────

  void _listenRoute() {
    _routeSub =
        FirestoreService.watchRoute(widget.driver.id).listen((stops) async {
      final today = _todayStr();
      final todayStops = stops
          .where((s) => s.date.isEmpty || s.date.compareTo(today) <= 0)
          .toList();
      setState(() {
        _allStops = stops;
        _stops = todayStops;
      });
      if (stops.length >= 2) {
        setState(() => _loadingRoute = true);
        final result = await MapboxService.getDirections(stops);
        if (mounted && result != null) {
          setState(() {
            _routePoints = result.route;
            _navSteps = result.steps;
            _totalDistance = result.distanceText;
            _totalDuration = result.durationText;
            _currentStep = 0;
            _loadingRoute = false;
          });
          if (_mapReady) _fitAllStops();
        } else if (mounted) {
          setState(() => _loadingRoute = false);
        }
      }
    });
  }

  // ─── מיקום ─────────────────────────────────────────────────────────────────

  Future<void> _initLocation() async {
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (mounted) {
        setState(() => _userPos = LatLng(pos.latitude, pos.longitude));
      }
    } catch (_) {}
  }

  void _startNavigation() {
    setState(() => _navStarted = true);
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      (pos) {
        final newPos = LatLng(pos.latitude, pos.longitude);
        if (mounted) {
          setState(() {
            _userPos = newPos;
            _advanceStep(newPos);
          });
          _mapController.move(newPos, _mapController.camera.zoom);
        }
      },
      onError: (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('לא ניתן לקבל מיקום GPS')),
          );
        }
      },
    );
  }

  void _stopNavigation() {
    _posSub?.cancel();
    _posSub = null;
    setState(() => _navStarted = false);
  }

  void _advanceStep(LatLng pos) {
    if (_navSteps.isEmpty || _currentStep >= _navSteps.length - 1) return;
    final step = _navSteps[_currentStep];
    if (step.points.isEmpty) return;
    final target = step.points.last;
    final dist =
        const Distance().as(LengthUnit.Meter, pos, target);
    if (dist < 25) setState(() => _currentStep++);
  }

  Future<void> _markStopDone(RouteStop stop) async {
    final remaining = _allStops.where((s) => s.id != stop.id).toList();
    await FirestoreService.saveRoute(widget.driver.id, remaining);
  }

  Future<void> _handleDone(RouteStop stop) async {
    // שלב 1: אישור
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('אישור סיום משלוח'),
          content: const Text('האם אתה בטוח שסיימת את המשלוח?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white),
              child: const Text('אישור'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    // שלב 2: הזנת סכום ואמצעי תשלום
    final ctrl = TextEditingController(text: stop.balance);
    final paymentMethods = ['מזומן', 'אשראי', 'העברה', 'ביט', "צ'ק"];
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        String selectedMethod = 'מזומן';
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setS) => AlertDialog(
              title: const Text('גבייה מהלקוח'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (stop.balance.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.attach_money, color: Colors.green),
                          const SizedBox(width: 6),
                          Text('יתרה לגבייה: ₪${stop.balance}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                        ],
                      ),
                    ),
                  TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'סכום שנגבה (₪)',
                      border: OutlineInputBorder(),
                      prefixText: '₪ ',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text('אמצעי תשלום',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey[600])),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: paymentMethods.map((method) {
                      final selected = method == selectedMethod;
                      return GestureDetector(
                        onTap: () => setS(() => selectedMethod = method),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF2E7D32)
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFF2E7D32)
                                  : Colors.grey[300]!,
                            ),
                          ),
                          child: Text(
                            method,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: selected ? Colors.white : Colors.grey[700],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('ביטול'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, {
                    'amount': ctrl.text.trim(),
                    'method': selectedMethod,
                  }),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white),
                  child: const Text('אישור'),
                ),
              ],
            ),
          ),
        );
      },
    );
    ctrl.dispose();
    if (result == null || !mounted) return;
    final amount = result['amount'] ?? '';
    final method = result['method'] ?? 'מזומן';

    // שמירת רשומת גבייה
    await FirestoreService.saveCompletedStop(
      driverId: widget.driver.id,
      driverName: widget.driver.name,
      address: stop.address,
      expectedBalance: stop.balance,
      collectedAmount: amount,
      paymentMethod: method,
      accountNumber: stop.accountNumber,
    );

    // הסרת העצירה מהמסלול
    await _markStopDone(stop);
  }

  // ─── מפה ───────────────────────────────────────────────────────────────────

  void _fitAllStops() {
    if (_stops.isEmpty) return;
    final points = _stops.map((s) => LatLng(s.lat, s.lng)).toList();
    if (_userPos != null) points.add(_userPos!);
    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(64)),
    );
  }

  // ─── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Stack(
          children: [
            _buildMap(),
            _buildTopBar(),
            if (_loadingRoute) _buildLoadingBadge(),
            if (_stops.isNotEmpty) _buildBottomPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _userPos ?? _defaultCenter,
        initialZoom: 13,
        onMapReady: () {
          setState(() => _mapReady = true);
          if (_stops.length >= 2) _fitAllStops();
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.gps.drivers',
          maxNativeZoom: 19,
        ),
        if (_routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                strokeWidth: 6,
                color: const Color(0xFF1565C0),
                borderStrokeWidth: 1.5,
                borderColor: Colors.white,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            ..._stops.asMap().entries.map((e) => _stopMarker(e.key, e.value)),
            if (_userPos != null) _userMarker(),
          ],
        ),
      ],
    );
  }

  Marker _stopMarker(int index, RouteStop stop) {
    final isLast = index == _stops.length - 1;
    return Marker(
      point: LatLng(stop.lat, stop.lng),
      width: 42,
      height: 42,
      child: GestureDetector(
        onTap: () => _showStopDetails(index, stop),
        child: Container(
          decoration: BoxDecoration(
            color: isLast ? Colors.red : const Color(0xFF1565C0),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2))
            ],
          ),
          child: Center(
            child: isLast
                ? const Icon(Icons.flag, color: Colors.white, size: 20)
                : Text('${index + 1}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
          ),
        ),
      ),
    );
  }

  Marker _userMarker() {
    return Marker(
      point: _userPos!,
      width: 40,
      height: 40,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.blue,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
                color: Colors.blue.withOpacity(0.4),
                blurRadius: 12,
                spreadRadius: 4),
          ],
        ),
        child: const Icon(Icons.navigation, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _mapBtn(Icons.arrow_back, () => Navigator.pop(context)),
              const SizedBox(width: 10),
              Expanded(
                child: _pill(
                  Row(
                    children: [
                      const Icon(Icons.local_shipping,
                          color: Color(0xFF1565C0), size: 20),
                      const SizedBox(width: 8),
                      Text(widget.driver.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _mapBtn(Icons.fit_screen, _fitAllStops,
                  tooltip: 'הצג מסלול מלא'),
              const SizedBox(width: 6),
              _mapBtn(Icons.receipt_long, _showCollectionsReport,
                  tooltip: 'דוח גבייה'),
              if (_navStarted) ...[
                const SizedBox(width: 6),
                _mapBtn(Icons.stop_circle, _stopNavigation,
                    tooltip: 'עצור ניווט', color: Colors.red),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _mapBtn(IconData icon, VoidCallback onTap,
      {String? tooltip, Color? color}) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 4,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: color ?? Colors.black87, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _pill(Widget child) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      child: child,
    );
  }

  Widget _buildLoadingBadge() {
    return Positioned(
      top: 80,
      left: 0,
      right: 0,
      child: Center(
        child: _pill(const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('מחשב מסלול...'),
          ],
        )),
      ),
    );
  }

  // ─── Bottom Panel ───────────────────────────────────────────────────────────

  Widget _buildBottomPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          boxShadow: [
            BoxShadow(
                color: Colors.black26, blurRadius: 20, offset: Offset(0, -4))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),

            // Route summary
            if (_totalDistance.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    _summaryChip(Icons.straighten, _totalDistance),
                    const SizedBox(width: 8),
                    _summaryChip(Icons.schedule, _totalDuration),
                    const SizedBox(width: 8),
                    _summaryChip(Icons.place, '${_stops.length} עצירות'),
                  ],
                ),
              ),

            // Navigation instruction or start button
            if (_navStarted && _navSteps.isNotEmpty)
              _buildNavInstruction()
            else
              _buildStartButton(),

            const Divider(height: 1),

            // Stops list
            _buildStopCards(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _summaryChip(IconData icon, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF1565C0)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ElevatedButton.icon(
        onPressed: _navSteps.isEmpty ? null : _startNavigation,
        icon: const Icon(Icons.navigation_rounded),
        label: const Text('התחל ניווט', style: TextStyle(fontSize: 16)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2E7D32),
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 2,
        ),
      ),
    );
  }

  Widget _buildNavInstruction() {
    if (_currentStep >= _navSteps.length) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 32),
            SizedBox(width: 12),
            Text('הגעת ליעד!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }
    final step = _navSteps[_currentStep];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(_maneuverIcon(step.maneuverType),
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.instruction,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 2),
                Text(step.distanceText,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ],
            ),
          ),
          Text(
            '${_currentStep + 1}/${_navSteps.length}',
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildStopCards() {
    return SizedBox(
      height: 150,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: _stops.length,
        itemBuilder: (ctx, i) {
          final stop = _stops[i];
          final isFirst = i == 0;
          final isLast = i == _stops.length - 1;
          final accent = isFirst
              ? Colors.green
              : isLast
                  ? Colors.red
                  : const Color(0xFF1565C0);
          return GestureDetector(
            onTap: () => _showStopDetails(i, stop),
            child: Container(
              width: 160,
              margin: const EdgeInsets.only(left: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 11,
                        backgroundColor: accent,
                        child: isLast
                            ? const Icon(Icons.flag,
                                color: Colors.white, size: 12)
                            : Text('${i + 1}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isFirst
                              ? 'התחלה'
                              : isLast
                                  ? 'סיום'
                                  : 'עצירה ${i + 1}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: accent),
                        ),
                      ),
                      const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Expanded(
                    child: Text(
                      stop.address,
                      style: const TextStyle(fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (stop.balance.isNotEmpty)
                    Text('₪${stop.balance}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.green)),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    height: 28,
                    child: ElevatedButton.icon(
                      onPressed: () => _handleDone(stop),
                      icon: const Icon(Icons.check, size: 13),
                      label: const Text('בוצע', style: TextStyle(fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showStopDetails(int index, RouteStop stop) {
    final isFirst = index == 0;
    final isLast = index == _stops.length - 1;
    final accent = isFirst
        ? Colors.green
        : isLast
            ? Colors.red
            : const Color(0xFF1565C0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),

              // Title row
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: accent,
                    radius: 18,
                    child: isLast
                        ? const Icon(Icons.flag, color: Colors.white, size: 18)
                        : Text('${index + 1}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isFirst
                          ? 'נקודת התחלה'
                          : isLast
                              ? 'נקודת סיום'
                              : 'עצירה ${index + 1}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: accent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Address
              Row(
                children: [
                  const Icon(Icons.location_on, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(stop.address,
                        style: const TextStyle(fontSize: 14)),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Account number
              if (stop.accountNumber.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_outlined,
                          color: Colors.indigo, size: 20),
                      const SizedBox(width: 8),
                      const Text('חשבון עסקה:',
                          style: TextStyle(fontSize: 14)),
                      const Spacer(),
                      Text('#${stop.accountNumber}',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // Phone 1
              if (stop.phone1.isNotEmpty)
                _phoneRow('טלפון 1', stop.phone1, Icons.phone),
              if (stop.phone1.isNotEmpty) const SizedBox(height: 10),

              // Phone 2
              if (stop.phone2.isNotEmpty)
                _phoneRow('טלפון 2', stop.phone2, Icons.phone_android),
              if (stop.phone2.isNotEmpty) const SizedBox(height: 10),

              // Balance
              if (stop.balance.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.attach_money,
                          color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      const Text('יתרה לגבייה:',
                          style: TextStyle(fontSize: 14)),
                      const Spacer(),
                      Text('₪${stop.balance}',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green)),
                    ],
                  ),
                ),
              if (stop.balance.isNotEmpty) const SizedBox(height: 16),

              // Waze button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    html.window.location.href =
                        'https://waze.com/ul?ll=${stop.lat},${stop.lng}&navigate=yes';
                  },
                  icon: const Text('🗺️'),
                  label: const Text('פתח בוואיז',
                      style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00AAFF),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _phoneRow(String label, String phone, IconData icon) {
    return InkWell(
      onTap: () {
        html.window.location.href = 'tel:$phone';
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF1565C0), size: 20),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
            const Spacer(),
            Text(phone,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            const Icon(Icons.call, color: Color(0xFF1565C0), size: 18),
          ],
        ),
      ),
    );
  }

  void _showCollectionsReport() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          builder: (ctx, scroll) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long, color: Color(0xFF1565C0)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'דוח גבייה - ${widget.driver.name}',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: FirestoreService.watchCompletedStops(widget.driver.id),
                    builder: (ctx, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final items = snap.data ?? [];
                      if (items.isEmpty) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inbox, size: 60, color: Colors.grey),
                              SizedBox(height: 12),
                              Text('אין גבייות עדיין',
                                  style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        );
                      }

                      double cashTotal = 0;
                      double allTotal = 0;
                      for (final item in items) {
                        final v = double.tryParse(
                                item['collectedAmount'] as String? ?? '') ?? 0;
                        allTotal += v;
                        if ((item['paymentMethod'] as String? ?? '') == 'מזומן') {
                          cashTotal += v;
                        }
                      }

                      return Column(
                        children: [
                          Container(
                            margin: const EdgeInsets.all(16),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.account_balance_wallet,
                                        color: Colors.green, size: 28),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${items.length} משלוחים',
                                            style: TextStyle(
                                                color: Colors.grey[700],
                                                fontSize: 13)),
                                        const Text('סה"כ גבייה',
                                            style: TextStyle(
                                                color: Colors.green,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                    const Spacer(),
                                    Text(
                                      '₪${cashTotal % 1 == 0 ? cashTotal.toInt() : cashTotal.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green),
                                    ),
                                  ],
                                ),
                                if (allTotal != cashTotal) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      const Icon(Icons.info_outline,
                                          size: 13, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(
                                        'כולל כל אמצעי תשלום: ₪${allTotal % 1 == 0 ? allTotal.toInt() : allTotal.toStringAsFixed(2)}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600]),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              controller: scroll,
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: items.length,
                              itemBuilder: (ctx, i) {
                                final item = items[i];
                                final collected =
                                    item['collectedAmount'] as String? ?? '';
                                final expected =
                                    item['expectedBalance'] as String? ?? '';
                                final address =
                                    item['address'] as String? ?? '';
                                final paymentMethod =
                                    item['paymentMethod'] as String? ?? '';
                                final accountNumber =
                                    item['accountNumber'] as String? ?? '';
                                final methodColor = _paymentColor(paymentMethod);
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundColor: const Color(0xFF1565C0),
                                          child: Text('${i + 1}',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13)),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(address,
                                                  style: const TextStyle(
                                                      fontSize: 13),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis),
                                              if (accountNumber.isNotEmpty)
                                                Text('#$accountNumber',
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.indigo,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                              if (expected.isNotEmpty)
                                                Text('יתרה: ₪$expected',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color:
                                                            Colors.grey[600])),
                                              if (paymentMethod.isNotEmpty)
                                                Container(
                                                  margin: const EdgeInsets.only(top: 4),
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: methodColor.withOpacity(0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(10),
                                                    border: Border.all(
                                                        color: methodColor
                                                            .withOpacity(0.4)),
                                                  ),
                                                  child: Text(paymentMethod,
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          color: methodColor,
                                                          fontWeight:
                                                              FontWeight.bold)),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '₪$collected',
                                          style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _paymentColor(String method) {
    switch (method) {
      case 'מזומן': return Colors.green;
      case 'אשראי': return Colors.blue;
      case 'העברה': return Colors.purple;
      case 'ביט': return const Color(0xFFE91E8C);
      case "צ'ק": return Colors.orange;
      default: return Colors.grey;
    }
  }

  IconData _maneuverIcon(String type) {
    switch (type) {
      case 'turn':
        return Icons.turn_right;
      case 'merge':
        return Icons.merge;
      case 'fork':
        return Icons.call_split;
      case 'ramp':
        return Icons.arrow_upward;
      case 'roundabout':
      case 'rotary':
        return Icons.roundabout_right;
      case 'arrive':
        return Icons.location_on;
      case 'depart':
        return Icons.directions_car;
      case 'end of road':
        return Icons.block;
      default:
        return Icons.straight;
    }
  }
}
