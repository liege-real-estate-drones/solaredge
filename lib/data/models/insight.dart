// lib/data/models/insight.dart
import 'package:flutter/material.dart';

// Types d'insights pour éventuellement adapter l'affichage (icône, couleur...)
enum InsightType {
  performance,
  savings,
  tip,
  alert,
  general,
  weather,
}

class Insight {
  final String title; // Titre de la carte d'info
  final String message; // Message principal
  final IconData? icon; // Icône à afficher
  final InsightType type; // Type d'info
  final Color?
      backgroundColor; // Couleur de fond optionnelle pour certains types

  Insight({
    required this.title,
    required this.message,
    required this.type,
    this.icon,
    this.backgroundColor,
  });
}
