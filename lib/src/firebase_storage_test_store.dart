import 'dart:convert';
import 'dart:typed_data';

import 'package:automated_testing_framework/automated_testing_framework.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:json_class/json_class.dart';
import 'package:logging/logging.dart';

/// Test Store for the Automated Testing Framework that can read and write tests
/// to Firebase Storage.
class FirebaseStorageTestStore {
  /// Initializes the test store.  This requires the [FirebaseStorage] to be
  /// assigned and initialized.
  ///
  /// The [imagePath] is optional and is the path within Firebase Storage where
  /// the screenshots must be saved.  If omitted, this defaults to 'images'.
  /// This only is utilized if the [storage] is not-null.  If the [storage] is
  /// null then this is ignored and screenshots are not uploaded.
  ///
  /// The [testCollectionPath] is optional and is the collection within Firebase
  /// Realtime Databse where the tests themselves must be saved.  If omitted,
  /// this defaults to 'tests'.
  ///
  /// The [reportCollectionPath] is optional and is the collection within
  /// Firebase Realtime Database where the test reports must be saved.  If
  /// omitted, this defaults to 'reports'.
  FirebaseStorageTestStore({
    this.imagePath,
    this.maxDataSize = 50 * 1024 * 1024, // 50mb
    this.reportCollectionPath,
    @required this.storage,
    this.testCollectionPath,
  }) : assert(storage != null);

  static final Logger _logger = Logger('FirebaseStorageTestStore');

  /// Optional path for screenshots to be uploated to within Firebase Storage.
  /// If [storage] is null or if this is on the web platform, this value is
  /// ignored.
  final String imagePath;

  final int maxDataSize;

  /// Optional collection path to store test reports.  If omitted, this defaults
  /// to 'reports'.  Provided to allow for a single Firebase instance the
  /// ability to host multiple applications or environments.
  final String reportCollectionPath;

  /// Optional [FirebaseStorage] reference object.  If set, and the platform is
  /// not web, then this will be used to upload screenshot results from test
  /// reports.  If omitted, screenshots will not be uploaded anywhere and will
  /// be lost if this test store is used for test reports.
  final FirebaseStorage storage;

  /// Optional collection path to store test data.  If omitted, this defaults
  /// to 'tests'.  Provided to allow for a single Firebase instance the ability
  /// to host multiple applications or environments.
  final String testCollectionPath;

  /// Implementation of the [TestReader] functional interface that can read test
  /// data from Firebase Realtime Database.
  Future<List<PendingTest>> testReader(
    BuildContext context, {
    String suiteName,
  }) async {
    List<PendingTest> results;

    try {
      results = [];
      var actualCollectionPath = (testCollectionPath ?? 'tests');

      var ref =
          storage.ref().child(actualCollectionPath).child('all_tests.json');
      var snapshot = await ref.getData(maxDataSize);
      var tests = json.decode(String.fromCharCodes(snapshot));

      tests.forEach((_, data) {
        var activeVersion = JsonClass.parseInt(data['activeVersion']);
        var id = data['name'];
        var pTest = PendingTest(
          loader: AsyncTestLoader(({bool ignoreImages}) async {
            var testData = await storage
                .ref()
                .child(actualCollectionPath)
                .child('${id}_$activeVersion.json')
                .getData(maxDataSize);

            var realData = json.decode(String.fromCharCodes(testData));
            return Test(
              active: true,
              name: realData['name'],
              steps: JsonClass.fromDynamicList(
                realData['steps'],
                (entry) => TestStep.fromDynamic(
                  entry,
                  ignoreImages: false,
                ),
              ),
              version: realData['version'],
            );
          }),
          name: data['name'],
          numSteps: JsonClass.parseInt(data['numSteps']),
          suiteName: data['suiteName'],
          version: activeVersion,
        );

        if (suiteName == null || suiteName == pTest.suiteName) {
          results.add(pTest);
        }
      });
    } catch (e, stack) {
      _logger.severe('Error loading tests', e, stack);
    }

    return results ?? <PendingTest>[];
  }

  /// Implementation of the [TestReport] functional interface that can submit
  /// test reports to Firebase Realtime Database.
  Future<bool> testReporter(TestReport report) async {
    var result = false;

    var actualCollectionPath = (reportCollectionPath ?? 'reports');

    var doc = storage
        .ref()
        .child(actualCollectionPath)
        .child(report.name)
        .child(report.version.toString())
        .child(
          '${report.deviceInfo.deviceSignature}_${report.startTime.millisecondsSinceEpoch}.json',
        );

    await doc
        .putData(
          Uint8List.fromList(
            json.encode({
              'deviceInfo': report.deviceInfo.toJson(),
              'endTime': report.endTime?.millisecondsSinceEpoch,
              'errorSteps': report.errorSteps,
              'images': report.images.map((entity) => entity.hash).toList(),
              'logs': report.logs,
              'name': report.name,
              'passedSteps': report.passedSteps,
              'runtimeException': report.runtimeException,
              'startTime': report.startTime?.millisecondsSinceEpoch,
              'steps': JsonClass.toJsonList(report.steps),
              'success': report.success,
              'suiteName': report.suiteName,
              'version': report.version,
            }).codeUnits,
          ),
          StorageMetadata(contentType: 'application/json'),
        )
        .onComplete;

    await uploadImages(report);

    return result;
  }

  /// Implementation of the [TestWriter] functional interface that can submit
  /// test data to Firebase Realtime Database.
  Future<bool> testWriter(
    BuildContext context,
    Test test,
  ) async {
    var result = false;

    try {
      var actualCollectionPath = (testCollectionPath ?? 'tests');

      var id = test.name;

      var ref =
          storage.ref().child(actualCollectionPath).child('all_tests.json');
      var tests = <String, dynamic>{};
      try {
        var snapshot = await ref.getData(double.maxFinite.toInt());
        tests = json.decode(String.fromCharCodes(snapshot));
      } catch (e) {
        // no-op; assume the file just doesn't exist
      }

      int version = (test.version ?? 0) + 1;
      tests[id] = {
        'activeVersion': version,
        'name': test.name,
        'numSteps': test.steps.length,
        'suiteName': test.suiteName,
      };
      var task = await storage
          .ref()
          .child(actualCollectionPath)
          .child('all_tests.json')
          .putData(
            Uint8List.fromList(json.encode(tests).codeUnits),
            StorageMetadata(contentType: 'application/json'),
          )
          .onComplete;
      if (task.error != null) {
        throw Exception(
            'Error writing: [$actualCollectionPath/all_tests.json] -- code: ${task.error}');
      }

      var testData = test
          .copyWith(
            version: version,
          )
          .toJson();

      task = await storage
          .ref()
          .child(actualCollectionPath)
          .child('${id}_$version.json')
          .putData(
            Uint8List.fromList(json.encode(testData).codeUnits),
            StorageMetadata(contentType: 'application/json'),
          )
          .onComplete;
      if (task.error != null) {
        throw Exception(
            'Error writing: [$actualCollectionPath/${id}_$version.json] -- code: ${task.error}');
      }

      result = true;
    } catch (e, stack) {
      _logger.severe('Error writing test', e, stack);
    }
    return result;
  }

  Future<void> uploadImages(TestReport report) async {
    if (!kIsWeb) {
      for (var image in report.images) {
        var actualImagePath = imagePath ?? 'images';
        var ref =
            storage.ref().child(actualImagePath).child('${image.hash}.png');
        var uploadTask = ref.putData(
          image.image,
          StorageMetadata(contentType: 'image/png'),
        );

        int lastProgress = -10;
        uploadTask.events.listen((event) {
          int progress =
              event.snapshot.bytesTransferred ~/ event.snapshot.totalByteCount;
          if (lastProgress + 10 <= progress) {
            _logger.log(Level.FINER, 'Image: ${image.hash} -- $progress%');
            lastProgress = progress;
          }
        });

        var task = await uploadTask.onComplete;
        _logger.log(Level.FINER, 'Image: ${image.hash} -- COMPLETE');
        if (task.error != null) {
          throw Exception(
              'Error writing: [$actualImagePath/${image.hash}.png] -- code: ${task.error}');
        }
      }
    }
  }
}
