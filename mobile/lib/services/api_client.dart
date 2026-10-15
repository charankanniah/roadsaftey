import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../core/config.dart';
import '../models/pothole.dart';

class ApiClient extends ChangeNotifier {
  String _baseUrl = AppConfig.defaultApiBaseUrl;
  String get baseUrl => _baseUrl;

  String _deviceId = '';
  String get deviceId => _deviceId;

  ApiClient() {
    _initDeviceId();
  }

  Future<void> _initDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? savedId = prefs.getString('potholeguard_device_id');
      if (savedId == null || savedId.isEmpty) {
        savedId = const Uuid().v4();
        await prefs.setString('potholeguard_device_id', savedId);
      }
      _deviceId = savedId;
      notifyListeners();
    } catch (_) {
      _deviceId = const Uuid().v4();
    }
  }

  void setBaseUrl(String newUrl) {
    _baseUrl = newUrl.trim().replaceAll(RegExp(r'/+$'), '');
    notifyListeners();
  }

  Future<bool> submitReport(Map<String, dynamic> report) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/reports'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(report),
      ).timeout(const Duration(seconds: 6));

      return response.statusCode == 201;
    } catch (e) {
      debugPrint('Error posting report to backend: $e');
      return false;
    }
  }

  Future<bool> submitBatchReports(List<Map<String, dynamic>> reports) async {
    if (reports.isEmpty) return true;
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/reports'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'reports': reports}),
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 201;
    } catch (e) {
      debugPrint('Error posting batch reports: $e');
      return false;
    }
  }

  Future<List<PotholeModel>> fetchNearbyPotholes({
    required double latitude,
    required double longitude,
    double radius = 1000.0,
    double? heading,
  }) async {
    try {
      final queryParams = {
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'radius': radius.toString(),
        if (heading != null) 'heading': heading.toString(),
      };

      final uri = Uri.parse('$_baseUrl/potholes/nearby').replace(queryParameters: queryParams);
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((item) => PotholeModel.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('Failed to query nearby potholes: $e');
    }
    return [];
  }
}
