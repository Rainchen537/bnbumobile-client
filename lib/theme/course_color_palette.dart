import 'package:flutter/material.dart';

import '../models/ta_course_entry.dart';
import '../models/timetable_data.dart';
import 'app_theme.dart';

abstract final class CourseColorPalette {
  static const List<double> _hueOffsets = <double>[
    0,
    32,
    72,
    118,
    164,
    206,
    248,
    286,
    318,
    46,
    142,
    228,
  ];

  static Map<String, Color> build(
    TimetableData timetable,
    Iterable<TaCourseEntry> taCourses,
    BnbuThemeExtension tokens,
  ) {
    final courseSeeds = timetable.courses.map(courseSeed).toSet().toList()
      ..sort();
    final taSeeds =
        taCourses
            .where((entry) => !entry.isTa)
            .map(taCourseSeed)
            .toSet()
            .toList()
          ..sort();
    return buildForSeeds(courseSeeds, taSeeds, tokens);
  }

  static Map<String, Color> buildForSeeds(
    Iterable<String> courseSeeds,
    Iterable<String> taSeeds,
    BnbuThemeExtension tokens,
  ) {
    final colorMap = <String, Color>{};
    final usedPaletteIndexes = <int>{};
    var overflowCount = 0;
    for (final seed in <String>[...courseSeeds, ...taSeeds]) {
      if (colorMap.containsKey(seed)) continue;
      final seedHash = seed.hashCode.abs();
      var paletteIndex = seedHash % _hueOffsets.length;
      var probeSteps = 0;
      while (usedPaletteIndexes.contains(paletteIndex) &&
          probeSteps < _hueOffsets.length) {
        paletteIndex = (paletteIndex + 1) % _hueOffsets.length;
        probeSteps++;
      }
      if (probeSteps < _hueOffsets.length) {
        usedPaletteIndexes.add(paletteIndex);
        colorMap[seed] = _colorAt(tokens, paletteIndex);
      } else {
        overflowCount++;
        colorMap[seed] = _colorAt(tokens, paletteIndex, overflowCount);
      }
    }
    return colorMap;
  }

  static String widgetHex(Color color) {
    final rgb = color.toARGB32() & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  static String courseSeed(TimetableCourse course) {
    return course.code.isNotEmpty ? course.code : course.name;
  }

  static String taCourseSeed(TaCourseEntry entry) =>
      entry.isTa ? entry.courseCode : 'ta:${entry.id}';

  static Color colorForCourse(
    TimetableCourse course,
    TimetableData timetable,
    BnbuThemeExtension tokens,
  ) {
    final seed = courseSeed(course);
    return build(timetable, const <TaCourseEntry>[], tokens)[seed] ??
        fallback(seed, tokens);
  }

  static Color fallback(String seed, BnbuThemeExtension tokens) {
    return _colorAt(tokens, seed.hashCode.abs() % _hueOffsets.length);
  }

  static Color _colorAt(
    BnbuThemeExtension tokens,
    int paletteIndex, [
    int variant = 0,
  ]) {
    final brand = HSLColor.fromColor(tokens.brandBlue);
    final darkCanvas =
        ThemeData.estimateBrightnessForColor(tokens.canvas) == Brightness.dark;
    final hue =
        (brand.hue + _hueOffsets[paletteIndex % _hueOffsets.length]) % 360;
    final saturation = (0.64 - variant * 0.035).clamp(0.46, 0.70).toDouble();
    final lightnessBase = darkCanvas ? 0.66 : 0.38;
    final lightness =
        (lightnessBase + (paletteIndex.isOdd ? 0.04 : 0) + variant * 0.025)
            .clamp(darkCanvas ? 0.56 : 0.30, darkCanvas ? 0.78 : 0.48)
            .toDouble();
    return HSLColor.fromAHSL(1, hue, saturation, lightness).toColor();
  }
}
