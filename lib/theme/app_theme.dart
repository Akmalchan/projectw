import 'package:flutter/material.dart';

class AppTheme {
  static const Color warmBackground = Color(0xFFFDFCF9);
  static const Color accentYellow = Color(0xFFFFD54F);
  static const Color prismaticLight = Color(0x80FFFFFF);

  static ThemeData lightTheme = ThemeData(
    scaffoldBackgroundColor: warmBackground,
    fontFamily: 'SF Pro Display',
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accentYellow,
      brightness: Brightness.light,
    ),
  );
}
