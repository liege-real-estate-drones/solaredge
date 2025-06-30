import 'dart:math';
import 'package:flutter/material.dart';
import 'package:solaredge_monitor/presentation/theme/app_theme.dart';

class PowerGaugeWidget extends StatelessWidget {
  final double powerValue; // Valeur actuelle en W
  final double percentage; // Pourcentage de la puissance maximale (0-1)
  final double maxPower; // Puissance maximale de l'installation en W
  
  const PowerGaugeWidget({
    super.key,
    required this.powerValue,
    required this.percentage,
    required this.maxPower,
  });

  @override
  Widget build(BuildContext context) {
    // Déterminer la couleur en fonction du pourcentage
    Color gaugeColor;
    if (percentage < 0.3) {
      gaugeColor = Colors.orange;
    } else if (percentage < 0.7) {
      gaugeColor = AppTheme.chartLine1; // Vert
    } else {
      gaugeColor = AppTheme.accentColor; // Vert plus foncé
    }
    
    // Formater la puissance pour l'affichage
    String formattedPower;
    String unit;
    
    if (powerValue >= 1000) {
      formattedPower = (powerValue / 1000).toStringAsFixed(2);
      unit = 'kW';
    } else {
      formattedPower = powerValue.toStringAsFixed(0);
      unit = 'W';
    }
    
    return Column(
      children: [
        SizedBox(
          height: 200,
          width: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Arc de fond
              CustomPaint(
                size: const Size(200, 200),
                painter: GaugePainter(
                  value: percentage,
                  color: gaugeColor,
                  backgroundColor: AppTheme.cardBorderColor.withOpacity(0.3),
                ),
              ),
              
              // Valeur de puissance au centre
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    formattedPower,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimaryColor,
                    ),
                  ),
                  Text(
                    unit,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondaryColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // Légende
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '0 W',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondaryColor,
                ),
              ),
              Text(
                maxPower >= 1000 
                    ? '${(maxPower / 1000).toStringAsFixed(1)} kW' 
                    : '${maxPower.toStringAsFixed(0)} W',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondaryColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class GaugePainter extends CustomPainter {
  final double value; // Value between 0 and 1
  final Color color;
  final Color backgroundColor;
  
  GaugePainter({
    required this.value,
    required this.color,
    required this.backgroundColor,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    
    // Angles for the arc (in radians)
    const startAngle = pi + pi / 6; // 210 degrees
    const sweepAngle = 4 * pi / 3; // 240 degrees
    
    // Background arc
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 12),
      startAngle,
      sweepAngle,
      false,
      backgroundPaint,
    );
    
    // Foreground arc (value)
    final foregroundPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 12),
      startAngle,
      sweepAngle * value, // Partial arc based on the value
      false,
      foregroundPaint,
    );
    
    // Draw ticks and labels
    _drawTicks(canvas, center, radius, 6); // 6 ticks = 5 segments
  }
  
  void _drawTicks(Canvas canvas, Offset center, double radius, int tickCount) {
    const startAngle = pi + pi / 6; // 210 degrees
    const sweepAngle = 4 * pi / 3; // 240 degrees
    
    final tickPaint = Paint()
      ..color = AppTheme.textSecondaryColor.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    
    for (int i = 0; i <= tickCount; i++) {
      final angle = startAngle + (sweepAngle / tickCount) * i;
      final outerPoint = Offset(
        center.dx + (radius - 6) * cos(angle),
        center.dy + (radius - 6) * sin(angle),
      );
      final innerPoint = Offset(
        center.dx + (radius - 18) * cos(angle),
        center.dy + (radius - 18) * sin(angle),
      );
      
      canvas.drawLine(innerPoint, outerPoint, tickPaint);
    }
  }
  
  @override
  bool shouldRepaint(GaugePainter oldDelegate) {
    return oldDelegate.value != value || 
           oldDelegate.color != color || 
           oldDelegate.backgroundColor != backgroundColor;
  }
}
