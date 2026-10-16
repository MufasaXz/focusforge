import 'package:flutter/material.dart';

import '../models/study.dart';
import 'app_strings.dart';

/// Stock plan names are display copy. A custom plan's name is user content,
/// even when it happens to match one of the stock English names.
String presetDisplayName(BuildContext context, PomodoroPreset preset) =>
    preset.id == null ? context.tr(preset.name) : preset.name;
