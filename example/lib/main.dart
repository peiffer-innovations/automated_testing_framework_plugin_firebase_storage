import 'dart:convert';

import 'package:automated_testing_framework/automated_testing_framework.dart';
import 'package:automated_testing_framework_example/automated_testing_framework_example.dart';
import 'package:automated_testing_framework_plugin_firebase_storage/automated_testing_framework_plugin_firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:websafe_platform/websafe_platform.dart';

void main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('${record.level.name}: ${record.time}: ${record.message}');
    if (record.error != null) {
      // ignore: avoid_print
      print('${record.error}');
    }
    if (record.stackTrace != null) {
      // ignore: avoid_print
      print('${record.stackTrace}');
    }
  });

  WidgetsFlutterBinding.ensureInitialized();

  var credentials =
      json.decode(await rootBundle.loadString('assets/login.json'));
  await Firebase.initializeApp();
  await FirebaseAuth.instance.signInWithEmailAndPassword(
    email: credentials['username'],
    password: credentials['password'],
  );

  var store = FirebaseStorageTestStore(
    storage: FirebaseStorage.instance,
  );

  var gestures = TestableGestures();
  var wsPlatform = WebsafePlatform();
  if (wsPlatform.isFuchsia() ||
      wsPlatform.isLinux() ||
      wsPlatform.isMacOS() ||
      wsPlatform.isWindows() ||
      wsPlatform.isWeb()) {
    gestures = TestableGestures(
      widgetLongPress: null,
      widgetSecondaryLongPress: TestableGestureAction.open_test_actions_page,
      widgetSecondaryTap: TestableGestureAction.open_test_actions_dialog,
    );
  }

  runApp(App(
    options: TestExampleOptions(
      autorun: kProfileMode,
      enabled: true,
      gestures: gestures,
      testReader: store.testReader,
      testReporter: store.testReporter,
      testWidgetsEnabled: true,
      testWriter: store.testWriter,
    ),
  ));
}
