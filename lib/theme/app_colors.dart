import 'package:flutter/material.dart';

class AppColors {
  // Base Palette - Earthy & Natural Theme
  static const Color cream = Color(0xFFF5F1E8);        // Lebih terang untuk background
  static const Color lightMint = Color(0xFFE8F3EA);    // Background alternatif
  static const Color mint = Color(0xFFA3C9A8);         // Accent terang
  static const Color sage = Color(0xFF6B9080);         // Primary yang lebih bold
  static const Color teal = Color(0xFF4A7C6F);         // Secondary yang lebih dalam
  static const Color deepTeal = Color(0xFF2F5D5D);     // Untuk AppBar/emphasis

  // Semantic Usage
  static const Color primary = sage;                    // Primary button, active states
  static const Color primaryDark = teal;                // Hover, pressed states
  static const Color secondary = mint;                  // Secondary actions
  static const Color accent = deepTeal;                 // Highlights, selected items
  static const Color background = cream;                // Screen background
  static const Color surface = lightMint;               // Cards, elevated components
  static const Color surfaceVariant = Color(0xFFFFFFFF); // White surface when needed

  static const Color textPrimary = Color(0xFF1A1A1A);   // Main text
  static const Color textSecondary = Color(0xFF5A5A5A); // Supporting text
  static const Color textTertiary = Color(0xFF8A8A8A);  // Disabled/hint text

  // Status Colors
  static const Color success = Color(0xFF6B9080);       // Success states
  static const Color warning = Color(0xFFE8B86D);       // Warnings
  static const Color error = Color(0xFFD17A6F);         // Errors
  static const Color info = Color(0xFF7B9EA8);          // Info messages

  // UI Elements
  static const Color divider = Color(0xFFE0E0E0);       // Dividers, borders
  static const Color shadow = Color(0x1A000000);        // Box shadows
}