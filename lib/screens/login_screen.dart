import 'package:flutter/material.dart';
import '../models/driver.dart';
import '../services/firestore_service.dart';
import 'manager_screen.dart';
import 'driver_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _showDriverList = false;

  Future<bool> _showPinDialog(String correctPin) async {
    final ctrl = TextEditingController();
    bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool hasError = false;
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setS) => AlertDialog(
              title: const Text('הזן קוד גישה'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: ctrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'קוד',
                      border: const OutlineInputBorder(),
                      errorText: hasError ? 'קוד שגוי, נסה שוב' : null,
                    ),
                    onSubmitted: (_) {
                      if (ctrl.text == correctPin) {
                        Navigator.pop(ctx, true);
                      } else {
                        setS(() => hasError = true);
                        ctrl.clear();
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('ביטול'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (ctrl.text == correctPin) {
                      Navigator.pop(ctx, true);
                    } else {
                      setS(() => hasError = true);
                      ctrl.clear();
                    }
                  },
                  child: const Text('כניסה'),
                ),
              ],
            ),
          ),
        );
      },
    );
    ctrl.dispose();
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              elevation: 12,
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.map, size: 72, color: Color(0xFF1565C0)),
                      const SizedBox(height: 16),
                      const Text(
                        'מערכת GPS נהגים',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'בחר את תפקידך להמשך',
                        style: TextStyle(fontSize: 15, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 40),
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 300),
                        crossFadeState: _showDriverList
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        firstChild: _buildRoleSelection(),
                        secondChild: _buildDriverSelection(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleSelection() {
    return Column(
      children: [
        _RoleCard(
          icon: Icons.admin_panel_settings_rounded,
          title: 'מנהל',
          subtitle: 'ניהול נהגים ומסלולים',
          color: const Color(0xFF1565C0),
          onTap: () async {
            final ok = await _showPinDialog('001324');
            if (ok && mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ManagerScreen()),
              );
            }
          },
        ),
        const SizedBox(height: 16),
        _RoleCard(
          icon: Icons.local_shipping_rounded,
          title: 'נהג',
          subtitle: 'הצג מסלול ומידע ניווט',
          color: const Color(0xFF2E7D32),
          onTap: () => setState(() => _showDriverList = true),
        ),
      ],
    );
  }

  Widget _buildDriverSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'בחר נהג',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        StreamBuilder<List<Driver>>(
          stream: FirestoreService.watchDrivers(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final drivers = snapshot.data ?? [];
            if (drivers.isEmpty) {
              return Column(
                children: [
                  Icon(Icons.person_off, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text('אין נהגים במערכת\nהמנהל צריך להוסיף נהגים תחילה',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600])),
                ],
              );
            }
            return Column(
              children: drivers
                  .map((d) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF2E7D32),
                            child: Text(
                              d.name.isNotEmpty ? d.name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(d.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          trailing:
                              const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () async {
                            final ok = await _showPinDialog(d.pin);
                            if (ok && mounted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DriverScreen(driver: d),
                                ),
                              );
                            }
                          },
                        ),
                      ))
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () => setState(() => _showDriverList = false),
          icon: const Icon(Icons.arrow_back),
          label: const Text('חזור'),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 32, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: color)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: color, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
