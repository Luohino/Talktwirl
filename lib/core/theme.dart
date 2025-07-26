import 'package:flutter/material.dart';

class AppTheme {
  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: Colors.black,
    scaffoldBackgroundColor: Colors.black,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.black,
      elevation: 0,
      centerTitle: true,
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontFamily: 'RoundedMplus', color: Colors.white),
      displayMedium: TextStyle(fontFamily: 'RoundedMplus', color: Colors.white),
      displaySmall: TextStyle(fontFamily: 'RoundedMplus', color: Colors.white),
      headlineMedium: TextStyle(fontFamily: 'RoundedMplus', color: Colors.white),
      headlineSmall: TextStyle(fontFamily: 'RoundedMplus', color: Colors.white),
      titleLarge: TextStyle(fontFamily: 'RoundedMplus', color: Colors.white),
      bodyLarge: TextStyle(fontFamily: 'RoundedMplus', color: Colors.white),
      bodyMedium: TextStyle(fontFamily: 'RoundedMplus', color: Colors.white),
      labelLarge: TextStyle(fontFamily: 'RoundedMplus', color: Colors.white),
    ),
    buttonTheme: const ButtonThemeData(
      buttonColor: Colors.black,
      textTheme: ButtonTextTheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16.0))),
    ),
    cardTheme: CardThemeData(
      color: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      elevation: 4,
      shadowColor: Colors.white.withOpacity(0.05),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.black,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16.0),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16.0),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16.0),
        borderSide: BorderSide(color: Colors.white, width: 2.0),
      ),
      labelStyle: TextStyle(color: Colors.grey[400]),
      hintStyle: TextStyle(color: Colors.grey[600]),
    ),
    dialogBackgroundColor: Colors.black,
    canvasColor: Colors.black,
    // Add more theme properties as needed
  );
}