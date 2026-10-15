import 'package:flutter/material.dart';
import '../core/theme.dart';

class PotholeModel {
  final int id;
  final double latitude;
  final double longitude;
  final double severityAvg;
  final int severityMax;
  final int confirmationCount;
  final String status;
  final DateTime firstDetectedAt;
  final DateTime lastDetectedAt;
  final double? distanceMeters;
  final double? bearing;
  final String? notes;

  PotholeModel({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.severityAvg,
    required this.severityMax,
    required this.confirmationCount,
    required this.status,
    required this.firstDetectedAt,
    required this.lastDetectedAt,
    this.distanceMeters,
    this.bearing,
    this.notes,
  });

  bool get isVerified => status == 'verified' || confirmationCount >= 3;
  bool get isFixed => status == 'fixed';
  bool get isPossiblyFixed => status == 'possibly_fixed';

  Color get color => AppTheme.getSeverityColor(severityMax);

  factory PotholeModel.fromJson(Map<String, dynamic> json) {
    return PotholeModel(
      id: json['id'] as int,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      severityAvg: (json['severity_avg'] as num?)?.toDouble() ?? 1.0,
      severityMax: json['severity_max'] as int? ?? 1,
      confirmationCount: json['confirmation_count'] as int? ?? 1,
      status: json['status'] as String? ?? 'new',
      firstDetectedAt: DateTime.tryParse(json['first_detected_at'] as String? ?? '') ?? DateTime.now(),
      lastDetectedAt: DateTime.tryParse(json['last_detected_at'] as String? ?? '') ?? DateTime.now(),
      distanceMeters: (json['distance_meters'] as num?)?.toDouble(),
      bearing: (json['bearing'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'severity_avg': severityAvg,
      'severity_max': severityMax,
      'confirmation_count': confirmationCount,
      'status': status,
      'first_detected_at': firstDetectedAt.toIso8601String(),
      'last_detected_at': lastDetectedAt.toIso8601String(),
      'distance_meters': distanceMeters,
      'bearing': bearing,
      'notes': notes,
    };
  }
}
