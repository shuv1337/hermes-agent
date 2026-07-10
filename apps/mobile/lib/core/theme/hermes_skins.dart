import 'package:flutter/material.dart';

/// Desktop-parity builtin skins (`apps/desktop/src/themes/presets.ts`).
///
/// Color tokens map 1:1 from DesktopThemeColors so mobile stays in sync when
/// we hand-port palette updates. Fonts are system defaults on mobile.
class HermesPalette {
  const HermesPalette({
    required this.background,
    required this.foreground,
    required this.card,
    required this.cardForeground,
    required this.muted,
    required this.mutedForeground,
    required this.primary,
    required this.primaryForeground,
    required this.secondary,
    required this.secondaryForeground,
    required this.accent,
    required this.accentForeground,
    required this.border,
    required this.input,
    required this.ring,
    required this.destructive,
    required this.destructiveForeground,
    this.sidebarBackground,
    this.userBubble,
  });

  final Color background;
  final Color foreground;
  final Color card;
  final Color cardForeground;
  final Color muted;
  final Color mutedForeground;
  final Color primary;
  final Color primaryForeground;
  final Color secondary;
  final Color secondaryForeground;
  final Color accent;
  final Color accentForeground;
  final Color border;
  final Color input;
  final Color ring;
  final Color destructive;
  final Color destructiveForeground;
  final Color? sidebarBackground;
  final Color? userBubble;
}

class HermesSkin {
  const HermesSkin({
    required this.id,
    required this.label,
    required this.description,
    required this.colors,
    this.darkColors,
  });

  final String id;
  final String label;
  final String description;

  /// Light palette (or only palette when [darkColors] is null).
  final HermesPalette colors;

  /// Hand-tuned dark palette when present (e.g. Nous).
  final HermesPalette? darkColors;

  /// Whether this skin is primarily dark (for preview swatches).
  bool get prefersDark {
    if (darkColors != null) return false; // dual-mode
    return ThemeData.estimateBrightnessForColor(colors.background) ==
        Brightness.dark;
  }

  HermesPalette paletteFor(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return darkColors ?? colors;
    }
    // Dual-mode skins use light [colors]; single dark skins still use colors
    // for light mode (Desktop reuses the same palette when darkColors is null).
    return colors;
  }
}

Color _hex(String raw) {
  var s = raw.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 6) s = 'FF$s';
  return Color(int.parse(s, radix: 16));
}

// ── Built-in skins (from desktop presets.ts) ─────────────────────────

const _nousBlue = Color(0xFF0053FD);
const _psycheBlue = Color(0xFF1540B1);
const _psycheWarm = Color(0xFFFFE6CB);

HermesPalette get _nousLight => HermesPalette(
  background: const Color(0xFFF8FAFF),
  foreground: const Color(0xFF17171A),
  card: const Color(0xFFFFFFFF),
  cardForeground: const Color(0xFF17171A),
  muted: Color.lerp(_nousBlue, Colors.white, 0.95)!,
  mutedForeground: const Color(0xFF666678),
  primary: _nousBlue,
  primaryForeground: const Color(0xFFFCFCFC),
  secondary: Color.lerp(_nousBlue, Colors.white, 0.93)!,
  secondaryForeground: const Color(0xFF242432),
  accent: Color.lerp(_nousBlue, Colors.white, 0.90)!,
  accentForeground: const Color(0xFF202030),
  border: _nousBlue.withValues(alpha: 0.22),
  input: _nousBlue.withValues(alpha: 0.30),
  ring: _nousBlue,
  destructive: const Color(0xFFC72E4D),
  destructiveForeground: Colors.white,
  sidebarBackground: const Color(0xFFF3F7FF),
  userBubble: Color.lerp(_nousBlue, Colors.white, 0.94)!,
);

HermesPalette get _nousDark => const HermesPalette(
  background: Color(0xFF0D2F86),
  foreground: _psycheWarm,
  card: Color(0xFF12378F),
  cardForeground: _psycheWarm,
  muted: Color(0xFF183F9A),
  mutedForeground: Color(0xFFB5C7F3),
  primary: _psycheWarm,
  primaryForeground: Color(0xFF0D2F86),
  secondary: Color(0xFF1B45A4),
  secondaryForeground: Color(0xFFE0E8FF),
  accent: _psycheBlue,
  accentForeground: Color(0xFFF0F4FF),
  border: Color(0xFF3158AD),
  input: Color(0xFF0B2566),
  ring: _psycheWarm,
  destructive: Color(0xFFC0473A),
  destructiveForeground: Color(0xFFFEF2F2),
  sidebarBackground: Color(0xFF09286F),
  userBubble: Color(0xFF143B91),
);

final HermesSkin nousSkin = HermesSkin(
  id: 'nous',
  label: 'Nous',
  description: 'Glass neutrals with Nous blue accents',
  colors: _nousLight,
  darkColors: _nousDark,
);

final HermesSkin midnightSkin = HermesSkin(
  id: 'midnight',
  label: 'Midnight',
  description: 'Deep blue-violet with cool accents',
  colors: HermesPalette(
    background: _hex('#08081c'),
    foreground: _hex('#ddd6ff'),
    card: _hex('#0d0d28'),
    cardForeground: _hex('#ddd6ff'),
    muted: _hex('#13133a'),
    mutedForeground: _hex('#7c7ab0'),
    primary: _hex('#ddd6ff'),
    primaryForeground: _hex('#08081c'),
    secondary: _hex('#1a1a4a'),
    secondaryForeground: _hex('#c4bff0'),
    accent: _hex('#1a1a44'),
    accentForeground: _hex('#d0c8ff'),
    border: _hex('#1e1e52'),
    input: _hex('#1e1e52'),
    ring: _hex('#8b80e8'),
    destructive: _hex('#b03060'),
    destructiveForeground: _hex('#fef2f2'),
    sidebarBackground: _hex('#06061a'),
    userBubble: _hex('#14143a'),
  ),
);

final HermesSkin emberSkin = HermesSkin(
  id: 'ember',
  label: 'Ember',
  description: 'Warm crimson and bronze — forge vibes',
  colors: HermesPalette(
    background: _hex('#160800'),
    foreground: _hex('#ffd8b0'),
    card: _hex('#1e0e04'),
    cardForeground: _hex('#ffd8b0'),
    muted: _hex('#2a1408'),
    mutedForeground: _hex('#aa7a56'),
    primary: _hex('#ffd8b0'),
    primaryForeground: _hex('#160800'),
    secondary: _hex('#341800'),
    secondaryForeground: _hex('#f0c090'),
    accent: _hex('#301600'),
    accentForeground: _hex('#e8c080'),
    border: _hex('#3a1c08'),
    input: _hex('#3a1c08'),
    ring: _hex('#d97316'),
    destructive: _hex('#c43010'),
    destructiveForeground: _hex('#fef2f2'),
    sidebarBackground: _hex('#100600'),
    userBubble: _hex('#2a1000'),
  ),
);

final HermesSkin monoSkin = HermesSkin(
  id: 'mono',
  label: 'Mono',
  description: 'Clean grayscale — minimal and focused',
  colors: HermesPalette(
    background: _hex('#0e0e0e'),
    foreground: _hex('#eaeaea'),
    card: _hex('#141414'),
    cardForeground: _hex('#eaeaea'),
    muted: _hex('#1e1e1e'),
    mutedForeground: _hex('#808080'),
    primary: _hex('#eaeaea'),
    primaryForeground: _hex('#0e0e0e'),
    secondary: _hex('#262626'),
    secondaryForeground: _hex('#c8c8c8'),
    accent: _hex('#222222'),
    accentForeground: _hex('#d8d8d8'),
    border: _hex('#2a2a2a'),
    input: _hex('#2a2a2a'),
    ring: _hex('#9a9a9a'),
    destructive: _hex('#a84040'),
    destructiveForeground: _hex('#fef2f2'),
    sidebarBackground: _hex('#0a0a0a'),
    userBubble: _hex('#1a1a1a'),
  ),
);

final HermesSkin cyberpunkSkin = HermesSkin(
  id: 'cyberpunk',
  label: 'Cyberpunk',
  description: 'Neon green on black — matrix terminal',
  colors: HermesPalette(
    background: _hex('#000a00'),
    foreground: _hex('#00ff41'),
    card: _hex('#001200'),
    cardForeground: _hex('#00ff41'),
    muted: _hex('#001a00'),
    mutedForeground: _hex('#1a8a30'),
    primary: _hex('#00ff41'),
    primaryForeground: _hex('#000a00'),
    secondary: _hex('#002800'),
    secondaryForeground: _hex('#00cc34'),
    accent: _hex('#002000'),
    accentForeground: _hex('#00e038'),
    border: _hex('#003000'),
    input: _hex('#003000'),
    ring: _hex('#00ff41'),
    destructive: _hex('#ff003c'),
    destructiveForeground: _hex('#000a00'),
    sidebarBackground: _hex('#000600'),
    userBubble: _hex('#001400'),
  ),
);

final HermesSkin slateSkin = HermesSkin(
  id: 'slate',
  label: 'Slate',
  description: 'Cool slate blue — focused developer theme',
  colors: HermesPalette(
    background: _hex('#0d1117'),
    foreground: _hex('#c9d1d9'),
    card: _hex('#161b22'),
    cardForeground: _hex('#c9d1d9'),
    muted: _hex('#21262d'),
    mutedForeground: _hex('#8b949e'),
    primary: _hex('#c9d1d9'),
    primaryForeground: _hex('#0d1117'),
    secondary: _hex('#2a3038'),
    secondaryForeground: _hex('#adb5bf'),
    accent: _hex('#1e2530'),
    accentForeground: _hex('#c0c8d0'),
    border: _hex('#30363d'),
    input: _hex('#30363d'),
    ring: _hex('#58a6ff'),
    destructive: _hex('#cf4848'),
    destructiveForeground: _hex('#fef2f2'),
    sidebarBackground: _hex('#090d13'),
    userBubble: _hex('#1e2a38'),
  ),
);

/// Desktop `BUILTIN_THEME_LIST` order.
final List<HermesSkin> kBuiltinSkins = [
  nousSkin,
  midnightSkin,
  emberSkin,
  monoSkin,
  cyberpunkSkin,
  slateSkin,
];

const kDefaultSkinId = 'nous';

HermesSkin skinById(String? id) {
  final key = (id ?? kDefaultSkinId).trim().toLowerCase();
  for (final s in kBuiltinSkins) {
    if (s.id == key) return s;
  }
  return nousSkin;
}

/// Build Flutter [ThemeData] from a desktop skin palette.
ThemeData buildThemeData(HermesSkin skin, Brightness brightness) {
  final p = skin.paletteFor(brightness);
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.primary,
    onPrimary: p.primaryForeground,
    secondary: p.ring,
    onSecondary: p.primaryForeground,
    surface: p.card,
    onSurface: p.foreground,
    error: p.destructive,
    onError: p.destructiveForeground,
    outline: p.border,
    surfaceContainerHighest: p.muted,
    surfaceContainerHigh: p.secondary,
    surfaceContainer: p.card,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.foreground,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: p.foreground,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: p.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: p.border, width: 0.5),
      ),
    ),
    dividerTheme: DividerThemeData(color: p.border, thickness: 0.5),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.input.withValues(
        alpha: brightness == Brightness.dark ? 0.35 : 0.15,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.ring, width: 1.2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: TextStyle(color: p.mutedForeground),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.primary,
      foregroundColor: p.primaryForeground,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.sidebarBackground ?? p.card,
      indicatorColor: p.primary.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? p.primary : p.mutedForeground,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? p.primary : p.mutedForeground);
      }),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.mutedForeground,
      textColor: p.foreground,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.card,
      contentTextStyle: TextStyle(color: p.foreground),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
    ),
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: p.foreground,
      displayColor: p.foreground,
    ),
  );
}
