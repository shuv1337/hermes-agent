import 'package:flutter/material.dart';

import 'package:hermes_mobile/core/theme/hermes_skins.dart';

/// Back-compat helpers — prefer [buildThemeData] + [skinById].
ThemeData buildHermesDarkTheme({String skinId = kDefaultSkinId}) {
  return buildThemeData(skinById(skinId), Brightness.dark);
}

ThemeData buildHermesLightTheme({String skinId = kDefaultSkinId}) {
  return buildThemeData(skinById(skinId), Brightness.light);
}
