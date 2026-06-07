import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/driver.dart';
import '../models/route_stop.dart';
import '../services/firestore_service.dart';
import '../services/mapbox_service.dart';

class ManagerScreen extends StatefulWidget {
  const ManagerScreen({super.key});

  @override
  State<ManagerScreen> createState() => _ManagerScreenState();
}

class _ManagerScreenState extends State<ManagerScreen> {
  Driver? _selectedDriver;
  List<RouteStop> _stops = []; // all stops across all dates
  String _workingDate = _dateStr(DateTime.now());

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<RouteStop> get _dateStops {
    final filtered = _stops.where((s) => s.date == _workingDate).toList();
    filtered.sort((a, b) => a.order.compareTo(b.order));
    return filtered;
  }

  Set<String> get _existingDates {
    final dates = _stops.map((s) => s.date).where((d) => d.isNotEmpty).toSet();
    return dates;
  }

  String _formatDateLabel(String dateStr) {
    try {
      final d = DateTime.parse(dateStr);
      final today = DateTime.now();
      final todayStr = _dateStr(today);
      final tomorrowStr = _dateStr(today.add(const Duration(days: 1)));
      if (dateStr == todayStr) return 'היום';
      if (dateStr == tomorrowStr) return 'מחר';
      const days = ['שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת', 'ראשון'];
      return 'יום ${days[d.weekday - 1]} ${d.day}/${d.month}';
    } catch (_) {
      return dateStr;
    }
  }

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  List<Map<String, dynamic>> _suggestions = [];
  bool _searching = false;
  bool _saving = false;
  final _uuid = const Uuid();

  Timer? _debounce;
  int _searchId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ─── פעולות על כתובות ─────────────────────────────────────────────────────

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() { _suggestions = []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 200), () => _doSearch(query.trim()));
  }

  Future<void> _doSearch(String query) async {
    final id = ++_searchId;
    final results = await MapboxService.geocode(query);
    if (mounted && id == _searchId) {
      setState(() { _suggestions = results; _searching = false; });
    }
  }

  Future<void> _addStop(Map<String, dynamic> place) async {
    _debounce?.cancel();
    setState(() {
      _suggestions = [];
      _searchCtrl.clear();
      _searching = false;
    });
    _searchFocus.unfocus();

    final details = await _showStopDetailsDialog(
      title: 'פרטי עצירה',
      subtitle: place['name'] as String,
    );
    if (details == null) return;

    final dateOrder = _dateStops.length;
    final stop = RouteStop(
      id: _uuid.v4(),
      address: place['name'] as String,
      lat: place['lat'] as double,
      lng: place['lng'] as double,
      order: dateOrder,
      date: _workingDate,
      accountNumber: details['accountNumber'] ?? '',
      phone1: details['phone1'] ?? '',
      phone2: details['phone2'] ?? '',
      balance: details['balance'] ?? '',
    );
    setState(() => _stops.add(stop));
  }

  Future<void> _removeStop(int index) async {
    final dateStops = _dateStops;
    final stopId = dateStops[index].id;
    setState(() {
      _stops.removeWhere((s) => s.id == stopId);
      // re-number within date
      final remaining = _dateStops;
      for (int i = 0; i < remaining.length; i++) {
        final idx = _stops.indexWhere((s) => s.id == remaining[i].id);
        if (idx != -1) _stops[idx] = _stops[idx].copyWith(order: i);
      }
    });
    if (_selectedDriver != null) {
      await FirestoreService.saveRoute(_selectedDriver!.id, _stops);
    }
  }

  void _reorderStop(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final dateStops = _dateStops;
      final item = dateStops.removeAt(oldIndex);
      dateStops.insert(newIndex, item);
      for (int i = 0; i < dateStops.length; i++) {
        final idx = _stops.indexWhere((s) => s.id == dateStops[i].id);
        if (idx != -1) _stops[idx] = _stops[idx].copyWith(order: i);
      }
    });
  }

  Future<void> _editStop(int index) async {
    final stop = _dateStops[index];
    final details = await _showStopDetailsDialog(
      title: 'עריכת פרטים',
      subtitle: stop.address,
      initial: {
        'accountNumber': stop.accountNumber,
        'phone1': stop.phone1,
        'phone2': stop.phone2,
        'balance': stop.balance,
      },
    );
    if (details == null) return;
    setState(() {
      final idx = _stops.indexWhere((s) => s.id == stop.id);
      if (idx != -1) {
        _stops[idx] = stop.copyWith(
          accountNumber: details['accountNumber'],
          phone1: details['phone1'],
          phone2: details['phone2'],
          balance: details['balance'],
        );
      }
    });
  }

  Future<Map<String, String>?> _showStopDetailsDialog({
    required String title,
    String? subtitle,
    Map<String, String>? initial,
  }) async {
    final accountCtrl = TextEditingController(text: initial?['accountNumber'] ?? '');
    final phone1Ctrl = TextEditingController(text: initial?['phone1'] ?? '');
    final phone2Ctrl = TextEditingController(text: initial?['phone2'] ?? '');
    final balanceCtrl = TextEditingController(text: initial?['balance'] ?? '');

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              if (subtitle != null)
                Text(subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailField(accountCtrl, 'חשבון עסקה', Icons.receipt_outlined, TextInputType.number),
                const SizedBox(height: 12),
                _detailField(phone1Ctrl, 'טלפון 1', Icons.phone, TextInputType.phone),
                const SizedBox(height: 12),
                _detailField(phone2Ctrl, 'טלפון 2', Icons.phone_android, TextInputType.phone),
                const SizedBox(height: 12),
                _detailField(balanceCtrl, 'יתרה לגבייה (₪)', Icons.attach_money, TextInputType.number),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, {
                'accountNumber': accountCtrl.text.trim(),
                'phone1': phone1Ctrl.text.trim(),
                'phone2': phone2Ctrl.text.trim(),
                'balance': balanceCtrl.text.trim(),
              }),
              child: const Text('אישור'),
            ),
          ],
        ),
      ),
    );

    accountCtrl.dispose();
    phone1Ctrl.dispose();
    phone2Ctrl.dispose();
    balanceCtrl.dispose();
    return result;
  }

  Widget _detailField(TextEditingController ctrl, String label, IconData icon,
      TextInputType type) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  void _showCollectionsReport() {
    if (_selectedDriver == null) {
      _snack('בחר נהג תחילה', isError: true);
      return;
    }
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
                // Handle
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
                          'דוח גבייה - ${_selectedDriver!.name}',
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
                    stream: FirestoreService.watchCompletedStops(
                        _selectedDriver!.id),
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
                                item['collectedAmount'] as String? ?? '') ??
                            0;
                        allTotal += v;
                        if ((item['paymentMethod'] as String? ?? '') == 'מזומן') {
                          cashTotal += v;
                        }
                      }

                      return Column(
                        children: [
                          // Total banner
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
                                      const Icon(Icons.info_outline, size: 13, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(
                                        'כולל כל אמצעי תשלום: ₪${allTotal % 1 == 0 ? allTotal.toInt() : allTotal.toStringAsFixed(2)}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: ctx,
                                  builder: (c) => Directionality(
                                    textDirection: TextDirection.rtl,
                                    child: AlertDialog(
                                      title: const Text('איפוס נתונים'),
                                      content: const Text(
                                          'האם למחוק את כל הגבייות? פעולה זו אינה הפיכה.'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, false),
                                          child: const Text('ביטול'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () =>
                                              Navigator.pop(c, true),
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red,
                                              foregroundColor: Colors.white),
                                          child: const Text('מחק הכל'),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                                if (ok == true) {
                                  await FirestoreService.clearCompletedStops(
                                      _selectedDriver!.id);
                                }
                              },
                              icon: const Icon(Icons.delete_sweep,
                                  color: Colors.red),
                              label: const Text('איפוס נתונים',
                                  style: TextStyle(color: Colors.red)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.red),
                                minimumSize: const Size(double.infinity, 44),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
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
                                                        fontWeight: FontWeight.bold)),
                                              if (expected.isNotEmpty)
                                                Text('יתרה: ₪$expected',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.grey[600])),
                                              if (paymentMethod.isNotEmpty)
                                                Container(
                                                  margin: const EdgeInsets.only(top: 4),
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: methodColor.withOpacity(0.12),
                                                    borderRadius: BorderRadius.circular(10),
                                                    border: Border.all(
                                                        color: methodColor.withOpacity(0.4)),
                                                  ),
                                                  child: Text(paymentMethod,
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          color: methodColor,
                                                          fontWeight: FontWeight.bold)),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '₪$collected',
                                              style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green),
                                            ),
                                            if (paymentMethod != 'מזומן' && paymentMethod.isNotEmpty)
                                              Text('לא נכלל בסה"כ',
                                                  style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                                          ],
                                        ),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          tooltip: 'ערוך',
                                          onPressed: () => _editCompletedStop(
                                            docId: item['docId'] as String? ?? '',
                                            currentAmount: collected,
                                            currentMethod: paymentMethod,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          tooltip: 'מחק',
                                          onPressed: () async {
                                            final docId = item['docId'] as String? ?? '';
                                            if (docId.isEmpty) return;
                                            final ok = await showDialog<bool>(
                                              context: ctx,
                                              builder: (c) => Directionality(
                                                textDirection: TextDirection.rtl,
                                                child: AlertDialog(
                                                  title: const Text('מחק גבייה'),
                                                  content: const Text('האם למחוק גבייה זו?'),
                                                  actions: [
                                                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ביטול')),
                                                    ElevatedButton(
                                                      onPressed: () => Navigator.pop(c, true),
                                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                                      child: const Text('מחק'),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                            if (ok == true) {
                                              await FirestoreService.deleteCompletedStop(docId);
                                            }
                                          },
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

  Future<void> _saveRoute() async {
    if (_selectedDriver == null) {
      _snack('בחר נהג תחילה', isError: true);
      return;
    }
    if (_stops.isEmpty) {
      _snack('הוסף לפחות כתובת אחת למסלול', isError: true);
      return;
    }
    setState(() => _saving = true);
    await FirestoreService.saveRoute(_selectedDriver!.id, _stops);
    if (mounted) {
      setState(() => _saving = false);
      _snack('המסלול נשמר בהצלחה!');
    }
  }

  Future<void> _clearRoute() async {
    if (_selectedDriver == null) return;
    final label = _formatDateLabel(_workingDate);
    final ok = await _confirm('נקה יום?', 'האם למחוק את כל עצירות $label?');
    if (!ok) return;
    setState(() => _stops.removeWhere((s) => s.date == _workingDate));
    await FirestoreService.saveRoute(_selectedDriver!.id, _stops);
    _snack('עצירות $label נמחקו');
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  Future<bool> _confirm(String title, String body) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: Text(title),
              content: Text(body),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('ביטול')),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('מחק', style: TextStyle(color: Colors.white))),
              ],
            ),
          ),
        ) ??
        false;
  }

  // ─── Date bar ────────────────────────────────────────────────────────────

  Widget _buildDateBar() {
    final existingDates = _existingDates.toList()..sort();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Navigation row
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: 'יום קודם',
                onPressed: () {
                  final d = DateTime.parse(_workingDate)
                      .subtract(const Duration(days: 1));
                  setState(() => _workingDate = _dateStr(d));
                },
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.parse(_workingDate),
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      locale: const Locale('he'),
                    );
                    if (picked != null) {
                      setState(() => _workingDate = _dateStr(picked));
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 15, color: Color(0xFF1565C0)),
                        const SizedBox(width: 6),
                        Text(
                          _formatDateLabel(_workingDate),
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1565C0)),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '(${_dateStops.length})',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: 'יום הבא',
                onPressed: () {
                  final d = DateTime.parse(_workingDate)
                      .add(const Duration(days: 1));
                  setState(() => _workingDate = _dateStr(d));
                },
              ),
            ],
          ),
          // Date chips
          if (existingDates.isNotEmpty)
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: existingDates.map((date) {
                  final isSelected = date == _workingDate;
                  final count = _stops.where((s) => s.date == date).length;
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _workingDate = date),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF1565C0)
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF1565C0)
                                : Colors.grey[300]!,
                          ),
                        ),
                        child: Text(
                          '${_formatDateLabel(date)} ($count)',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                isSelected ? Colors.white : Colors.grey[700],
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ─── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          title: const Text('ניהול מסלולים'),
          centerTitle: true,
          backgroundColor: const Color(0xFF1565C0),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.receipt_long),
              tooltip: 'דוח גבייה',
              onPressed: _showCollectionsReport,
            ),
          if (_dateStops.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_sweep),
                tooltip: 'נקה יום',
                onPressed: _clearRoute,
              ),
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.save_rounded),
                tooltip: 'שמור מסלול',
                onPressed: _saveRoute,
              ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                _buildDriverSelector(),
                _buildDateBar(),
                _buildSearchBar(),
                Expanded(child: _buildStopsList()),
              ],
            ),
            // Suggestions float above the list
            if (_suggestions.isNotEmpty || _searching)
              Positioned(
                top: 124,
                left: 16,
                right: 16,
                child: _buildSuggestions(),
              ),
          ],
        ),
        floatingActionButton: _dateStops.isNotEmpty
            ? FloatingActionButton.extended(
                onPressed: _saveRoute,
                icon: const Icon(Icons.save_rounded),
                label: Text('שמור · ${_dateStops.length} עצירות ${_formatDateLabel(_workingDate)}'),
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
              )
            : null,
      ),
    );
  }

  Widget _buildDriverSelector() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: StreamBuilder<List<Driver>>(
        stream: FirestoreService.watchDrivers(),
        builder: (context, snapshot) {
          final drivers = snapshot.data ?? [];
          return Row(
            children: [
              const Icon(Icons.person, color: Color(0xFF1565C0), size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<Driver>(
                  value: _selectedDriver != null &&
                          drivers.any((d) => d.id == _selectedDriver!.id)
                      ? drivers.firstWhere((d) => d.id == _selectedDriver!.id)
                      : null,
                  hint: const Text('בחר נהג'),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  items: drivers
                      .map((d) => DropdownMenuItem(value: d, child: Text(d.name)))
                      .toList(),
                  onChanged: (d) async {
                    setState(() {
                      _selectedDriver = d;
                      _stops = [];
                    });
                    if (d != null) {
                      final existing = await FirestoreService.watchRoute(d.id).first;
                      if (mounted) setState(() => _stops = List.from(existing));
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              _iconBtn(Icons.person_add_alt_1, 'הוסף נהג', _showAddDriverDialog),
              if (_selectedDriver != null) ...[
                const SizedBox(width: 4),
                _iconBtn(Icons.person_remove_alt_1, 'מחק נהג', _deleteSelectedDriver,
                    color: Colors.red),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        decoration: InputDecoration(
          hintText: 'חפש כתובת להוספה...',
          prefixIcon: _searching
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : const Icon(Icons.search),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _debounce?.cancel();
                    _searchCtrl.clear();
                    setState(() { _suggestions = []; _searching = false; });
                  },
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          isDense: true,
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _buildSuggestions() {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: _searching && _suggestions.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 12),
                    Text('מחפש...'),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: _suggestions
                    .map((s) => InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _addStop(s),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                const Icon(Icons.location_on, color: Color(0xFF1565C0), size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(s['name'] as String,
                                      style: const TextStyle(fontSize: 13)),
                                ),
                              ],
                            ),
                          ),
                        ))
                    .toList(),
              ),
      ),
    );
  }

  Widget _buildStopsList() {
    final dateStops = _dateStops;
    if (dateStops.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.route, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              _selectedDriver == null
                  ? 'בחר נהג ותוסיף כתובות'
                  : 'חפש כתובת להוספה ל${_formatDateLabel(_workingDate)}',
              style: TextStyle(fontSize: 16, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            'עצירות ${_formatDateLabel(_workingDate)} (${dateStops.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
            itemCount: dateStops.length,
            onReorder: _reorderStop,
            itemBuilder: (ctx, i) {
              final stop = dateStops[i];
              final hasDetails = stop.accountNumber.isNotEmpty ||
                  stop.phone1.isNotEmpty ||
                  stop.phone2.isNotEmpty ||
                  stop.balance.isNotEmpty;
              return Card(
                key: ValueKey(stop.id),
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: i == _stops.length - 1
                          ? Colors.red
                          : const Color(0xFF1565C0),
                      child: i == _stops.length - 1
                          ? const Icon(Icons.flag, color: Colors.white, size: 18)
                          : Text('${i + 1}',
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(stop.address, style: const TextStyle(fontSize: 13)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (i == 0)
                          const Text('נקודת התחלה',
                              style: TextStyle(color: Color(0xFF2E7D32), fontSize: 11))
                        else if (i == _stops.length - 1)
                          const Text('נקודת סיום',
                              style: TextStyle(color: Colors.red, fontSize: 11)),
                        if (hasDetails)
                          Wrap(
                            spacing: 8,
                            children: [
                              if (stop.accountNumber.isNotEmpty)
                                _miniChip(Icons.receipt_outlined, '#${stop.accountNumber}',
                                    color: Colors.indigo),
                              if (stop.phone1.isNotEmpty)
                                _miniChip(Icons.phone, stop.phone1),
                              if (stop.phone2.isNotEmpty)
                                _miniChip(Icons.phone_android, stop.phone2),
                              if (stop.balance.isNotEmpty)
                                _miniChip(Icons.attach_money, '₪${stop.balance}',
                                    color: Colors.green),
                            ],
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              color: Color(0xFF1565C0), size: 20),
                          tooltip: 'ערוך פרטים',
                          onPressed: () => _editStop(i),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red, size: 20),
                          onPressed: () => _removeStop(i),
                        ),
                        const Icon(Icons.drag_handle, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _editCompletedStop({
    required String docId,
    required String currentAmount,
    required String currentMethod,
  }) async {
    if (docId.isEmpty) return;
    final ctrl = TextEditingController(text: currentAmount);
    final paymentMethods = ['מזומן', 'אשראי', 'העברה', 'ביט', "צ'ק"];
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        String selectedMethod = paymentMethods.contains(currentMethod) ? currentMethod : 'מזומן';
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setS) => AlertDialog(
              title: const Text('עריכת גבייה'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                        style: TextStyle(fontSize: 13, color: Colors.grey[600])),
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
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFF2E7D32) : Colors.grey[100],
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected ? const Color(0xFF2E7D32) : Colors.grey[300]!,
                            ),
                          ),
                          child: Text(
                            method,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
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
                  child: const Text('שמור'),
                ),
              ],
            ),
          ),
        );
      },
    );
    ctrl.dispose();
    if (result == null) return;
    await FirestoreService.updateCompletedStop(
      docId: docId,
      collectedAmount: result['amount'] ?? '',
      paymentMethod: result['method'] ?? 'מזומן',
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

  Widget _miniChip(IconData icon, String text, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color ?? Colors.grey[600]),
        const SizedBox(width: 2),
        Text(text,
            style: TextStyle(fontSize: 11, color: color ?? Colors.grey[700])),
      ],
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onPressed,
      {Color? color}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: color ?? const Color(0xFF1565C0)),
        ),
      ),
    );
  }

  Future<void> _deleteSelectedDriver() async {
    if (_selectedDriver == null) return;
    final ok = await _confirm(
      'מחק נהג',
      'האם למחוק את הנהג "${_selectedDriver!.name}"?\nהמסלול וכל הנתונים שלו יימחקו.',
    );
    if (!ok) return;
    final id = _selectedDriver!.id;
    setState(() {
      _selectedDriver = null;
      _stops = [];
    });
    await FirestoreService.deleteDriver(id);
    await FirestoreService.clearCompletedStops(id);
    _snack('הנהג נמחק');
  }

  void _showAddDriverDialog() {
    final nameCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('הוסף נהג חדש'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'שם הנהג',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                autofocus: true,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: pinCtrl,
                decoration: const InputDecoration(
                  labelText: 'קוד כניסה (PIN)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                  hintText: 'לדוגמה: 1234',
                ),
                keyboardType: TextInputType.number,
                obscureText: false,
                onSubmitted: (_) => _submitAddDriver(nameCtrl, pinCtrl, ctx),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ביטול')),
            ElevatedButton(
                onPressed: () => _submitAddDriver(nameCtrl, pinCtrl, ctx),
                child: const Text('הוסף')),
          ],
        ),
      ),
    );
  }

  Future<void> _submitAddDriver(
      TextEditingController nameCtrl,
      TextEditingController pinCtrl,
      BuildContext ctx) async {
    if (nameCtrl.text.trim().isEmpty) return;
    final pin = pinCtrl.text.trim().isEmpty ? '1111' : pinCtrl.text.trim();
    await FirestoreService.addDriver(nameCtrl.text.trim(), pin);
    if (ctx.mounted) Navigator.pop(ctx);
  }
}
