import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/pothole.dart';
import 'api_client.dart';

class OfflineQueue extends ChangeNotifier {
  Database? _db;
  bool _isSyncing = false;
  int _pendingCount = 0;
  int get pendingCount => _pendingCount;

  Future<void> init() async {
    if (_db != null) return;
    try {
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, 'potholeguard_offline.db');

      _db = await openDatabase(
        path,
        version: 1,
        onCreate: (Database db, int version) async {
          // Table for queued un-synced reports
          await db.execute('''
            CREATE TABLE IF NOT EXISTS offline_reports (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              payload TEXT NOT NULL,
              retry_count INTEGER DEFAULT 0,
              created_at TEXT NOT NULL
            )
          ''');

          // Table for locally cached potholes for offline alert lookahead
          await db.execute('''
            CREATE TABLE IF NOT EXISTS cached_potholes (
              id INTEGER PRIMARY KEY,
              latitude REAL NOT NULL,
              longitude REAL NOT NULL,
              severity_avg REAL NOT NULL,
              severity_max INTEGER NOT NULL,
              confirmation_count INTEGER NOT NULL,
              status TEXT NOT NULL,
              first_detected_at TEXT,
              last_detected_at TEXT
            )
          ''');
        },
      );

      await _refreshPendingCount();
    } catch (e) {
      debugPrint('Error opening SQLite offline queue: $e');
    }
  }

  Future<void> _refreshPendingCount() async {
    if (_db == null) return;
    try {
      final result = await _db!.rawQuery('SELECT COUNT(*) as cnt FROM offline_reports');
      _pendingCount = Sqflite.firstIntValue(result) ?? 0;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> enqueueReport(Map<String, dynamic> report) async {
    if (_db == null) await init();
    try {
      await _db!.insert('offline_reports', {
        'payload': jsonEncode(report),
        'retry_count': 0,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _refreshPendingCount();
    } catch (e) {
      debugPrint('Error enqueueing offline report: $e');
    }
  }

  Future<void> syncPendingReports(ApiClient apiClient) async {
    if (_db == null || _isSyncing) return;
    _isSyncing = true;

    try {
      final List<Map<String, dynamic>> records = await _db!.query(
        'offline_reports',
        orderBy: 'id ASC',
        limit: 25,
      );

      if (records.isEmpty) {
        _isSyncing = false;
        return;
      }

      final List<Map<String, dynamic>> batchPayloads = [];
      final List<int> recordIds = [];

      for (var row in records) {
        recordIds.add(row['id'] as int);
        batchPayloads.add(jsonDecode(row['payload'] as String) as Map<String, dynamic>);
      }

      final bool success = await apiClient.submitBatchReports(batchPayloads);
      if (success) {
        // Delete uploaded records
        await _db!.delete(
          'offline_reports',
          where: 'id IN (${recordIds.join(',')})',
        );
        debugPrint('Successfully synchronized ${recordIds.length} offline reports.');
      } else {
        // Increment retry count
        await _db!.rawUpdate(
          'UPDATE offline_reports SET retry_count = retry_count + 1 WHERE id IN (${recordIds.join(',')})',
        );
      }

      await _refreshPendingCount();
    } catch (e) {
      debugPrint('Error syncing offline queue: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> cachePotholes(List<PotholeModel> potholes) async {
    if (_db == null || potholes.isEmpty) return;
    try {
      final batch = _db!.batch();
      for (var p in potholes) {
        batch.insert(
          'cached_potholes',
          {
            'id': p.id,
            'latitude': p.latitude,
            'longitude': p.longitude,
            'severity_avg': p.severityAvg,
            'severity_max': p.severityMax,
            'confirmation_count': p.confirmationCount,
            'status': p.status,
            'first_detected_at': p.firstDetectedAt.toIso8601String(),
            'last_detected_at': p.lastDetectedAt.toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('Error caching potholes locally: $e');
    }
  }

  Future<List<PotholeModel>> getCachedPotholes() async {
    if (_db == null) await init();
    try {
      final rows = await _db!.query('cached_potholes');
      return rows.map((r) => PotholeModel.fromJson(r)).toList();
    } catch (_) {
      return [];
    }
  }
}
