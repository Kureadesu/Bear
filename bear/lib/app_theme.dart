import 'package:material_ui/material_ui.dart';

const navyBackground = Color(0xFF090F20);
const navySurface = Color(0xFF121E35);
const bearBlue = Color(0xFF9CBFFF);

ThemeData buildBearTheme() {
  final colors =
      ColorScheme.fromSeed(
        seedColor: bearBlue,
        brightness: Brightness.dark,
      ).copyWith(
        primary: bearBlue,
        onPrimary: const Color(0xFF102342),
        secondary: const Color(0xFFE7AEC7),
        surface: navySurface,
        onSurface: const Color(0xFFEBF0FB),
      );
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(20),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colors,
    scaffoldBackgroundColor: navyBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: navyBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: navySurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: rounded,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF17253F),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF314462)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: bearBlue, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
        shape: rounded,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
        shape: rounded,
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: navySurface,
      indicatorColor: Color(0xFF29456C),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: navySurface,
      indicatorColor: Color(0xFF29456C),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Color(0xFF293E60),
      contentTextStyle: TextStyle(color: Colors.white),
    ),
  );
}
