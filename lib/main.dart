import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notes/app.dart';

// The home screen widgets' worker runs in an engine of its own, not from
// here; exported so the build keeps it.
export 'package:notes/data/home_widgets/widget_worker.dart' show widgetWorker;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  // A phone app used upright only; the manifest locks the activity too, so
  // the screen does not turn before Flutter starts.
  unawaited(
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
  );
  runApp(const ProviderScope(child: NotesApp()));
}
