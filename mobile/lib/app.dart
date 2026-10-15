import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'services/alert_service.dart';
import 'services/api_client.dart';
import 'services/location_service.dart';
import 'services/offline_queue.dart';
import 'services/sensor_service.dart';
import 'screens/home_screen.dart';
import 'screens/report_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';

class PotholeGuardApp extends StatelessWidget {
  const PotholeGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ApiClient()),
        ChangeNotifierProvider(create: (_) => LocationService()),
        ChangeNotifierProvider(create: (_) => OfflineQueue()),
        ChangeNotifierProxyProvider3<ApiClient, LocationService, OfflineQueue, SensorService>(
          create: (ctx) => SensorService(
            apiClient: ctx.read<ApiClient>(),
            locationService: ctx.read<LocationService>(),
            offlineQueue: ctx.read<OfflineQueue>(),
          ),
          update: (_, apiClient, locationService, offlineQueue, previous) =>
              previous ?? SensorService(
                apiClient: apiClient,
                locationService: locationService,
                offlineQueue: offlineQueue,
              ),
        ),
        ChangeNotifierProxyProvider3<ApiClient, LocationService, OfflineQueue, AlertService>(
          create: (ctx) => AlertService(
            apiClient: ctx.read<ApiClient>(),
            locationService: ctx.read<LocationService>(),
            offlineQueue: ctx.read<OfflineQueue>(),
          ),
          update: (_, apiClient, locationService, offlineQueue, previous) =>
              previous ?? AlertService(
                apiClient: apiClient,
                locationService: locationService,
                offlineQueue: offlineQueue,
              ),
        ),
      ],
      child: MaterialApp(
        title: 'PotholeGuard',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const _ConsentGate(),
      ),
    );
  }
}

/// First-launch consent gate before granting full access
class _ConsentGate extends StatelessWidget {
  const _ConsentGate();

  @override
  Widget build(BuildContext context) {
    // In production, check SharedPreferences for consent flag
    // For this MVP, proceed directly to main shell
    return const _AppShell();
  }
}

/// Bottom navigation shell
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int _currentIndex = 0;

  static const List<Widget> _screens = [
    HomeScreen(),
    ReportScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        backgroundColor: AppTheme.surfaceDark,
        indicatorColor: AppTheme.accentCyan.withOpacity(0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined, color: Colors.white60),
            selectedIcon: Icon(Icons.map, color: AppTheme.accentCyan),
            label: 'Drive',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline, color: Colors.white60),
            selectedIcon: Icon(Icons.add_circle, color: AppTheme.accentCyan),
            label: 'Report',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined, color: Colors.white60),
            selectedIcon: Icon(Icons.history, color: AppTheme.accentCyan),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined, color: Colors.white60),
            selectedIcon: Icon(Icons.settings, color: AppTheme.accentCyan),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
