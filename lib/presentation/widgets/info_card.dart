// lib/presentation/widgets/info_card.dart
import 'package:flutter/material.dart';
import 'package:solaredge_monitor/data/models/insight.dart'; // Importe le modèle Insight

class InfoCard extends StatelessWidget {
  final Insight insight;

  const InfoCard({super.key, required this.insight});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Détermine la couleur de l'icône en fonction du type (optionnel)
    Color iconColor = _getIconColor(insight.type, theme);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
      elevation: 2.0,
      color: insight.backgroundColor, // Utilise la couleur de fond si définie
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0), // Coins un peu plus arrondis
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            vertical: 12.0, horizontal: 16.0), // Ajuste le padding
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (insight.icon != null)
              Padding(
                padding: const EdgeInsets.only(
                    right: 16.0, top: 2.0), // Espace à droite de l'icône
                child: Icon(insight.icon,
                    color: iconColor, size: 32), // Icône légèrement plus grande
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    insight.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      // color: theme.colorScheme.onSurface // Assure une bonne lisibilité
                    ),
                  ),
                  const SizedBox(height: 6.0), // Espace accru
                  Text(
                    insight.message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        // color: theme.colorScheme.onSurfaceVariant // Couleur légèrement atténuée pour le corps
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper pour déterminer la couleur de l'icône (optionnel)
  Color _getIconColor(InsightType type, ThemeData theme) {
    // Utilise les couleurs du thème pour une meilleure cohérence
    final colorScheme = theme.colorScheme;
    switch (type) {
      case InsightType.savings:
        return Colors.green.shade600; // Vert pour économies
      case InsightType.alert:
        return colorScheme.error; // Rouge/Orange du thème pour alertes
      case InsightType.weather:
        return Colors.blue.shade600; // Bleu pour météo
      case InsightType.performance:
        return colorScheme.secondary; // Couleur secondaire pour performance
      case InsightType.tip:
        return Colors.blueGrey.shade500; // Gris-bleu pour conseils
      case InsightType.general:
      default:
        return colorScheme.primary; // Couleur primaire par défaut
    }
  }
}
