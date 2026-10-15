import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/alert_service.dart';

class AlertBanner extends StatelessWidget {
  final ActiveAlert alert;

  const AlertBanner({super.key, required this.alert});

  @override
  Widget build(BuildContext context) {
    final bool isImminent = alert.stage == AlertStage.imminent;
    final int severity = alert.pothole.severityMax;
    final Color bg = isImminent ? AppTheme.severityCritical : AppTheme.getSeverityColor(severity);
    final Color textColor = Colors.white;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
      decoration: BoxDecoration(
        color: bg,
        boxShadow: [BoxShadow(color: bg.withOpacity(0.55), blurRadius: 24, spreadRadius: 4)],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Warning Icon
            Icon(
              isImminent ? Icons.warning_rounded : Icons.report_problem_rounded,
              color: textColor,
              size: isImminent ? 42 : 36,
            ),
            const SizedBox(width: 14),
            // Alert Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isImminent ? '⚠️  POTHOLE NOW!' : '🚨  POTHOLE AHEAD',
                    style: TextStyle(
                      color: textColor,
                      fontSize: isImminent ? 26 : 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isImminent
                        ? 'SLOW DOWN IMMEDIATELY'
                        : '${alert.distanceMeters.round()} m  •  Severity ${severity}/5',
                    style: TextStyle(
                      color: textColor.withOpacity(0.92),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            // Severity badge
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                '$severity',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
