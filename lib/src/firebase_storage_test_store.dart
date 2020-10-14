import 'dart:convert';
import 'dart:io';
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

  /// The maximum size for data.  Due to Android's unit, ensure this remains
  /// less than a signed 32 bit max value or else it will crash on Android.
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

  /// Cached value that will be refreshed as needed.
  GoldenTestImages _currentGoldenTestImages;

  /// Downloads an image with the given [hash] from Cloud Firestore.  Will
  /// return [null] if the [hash] is [null].  Will throw an exception if [hash]
  /// is not [null] but could not be retrieved.
  Future<Uint8List> downloadImage(String hash) async {
    Uint8List image;
    var actualImagePath = imagePath ?? 'images';
    if (hash != null) {
      var ref = storage.ref().child(actualImagePath).child('$hash.png');
      image = await ref.getData(maxDataSize);
    }

    return image;
  }

  /// Downloads a text file from Cloud Firestore.  If the text file was encoded
  /// via GZIP, this will first decode it and then return the string.  The
  /// [children] must contain one or more path elements to the location of the
  /// text file.
  Future<String> downloadTextFile(List<String> children) async {
    var ref = storage.ref();
    for (var child in children) {
      ref = ref.child(child);
    }

    var data = await ref.getData(maxDataSize);

    return utf8.decode(data);
  }

  /// Writes the golden images from the [report] to Cloud Storage and also
  /// writes the metadata that allows the reading of the golden images.  This
  /// will throw an exception on failure.
  Future<void> goldenImageWriter(TestReport report) async {
    var actualCollectionPath = '${testCollectionPath ?? 'tests'}/goldens';

    var suitePrefix =
        report.suiteName?.isNotEmpty == true ? '${report.suiteName}_' : '';
    var name =
        '${suitePrefix}${report.name}_${report.deviceInfo.os}_${report.deviceInfo.orientation}_${report.deviceInfo.pixels.width}x${report.deviceInfo.pixels.height}.json';

    var data = <String, String>{};
    for (var image in (report.images ?? <TestImage>[])) {
      if (image.goldenCompatible == true) {
        data[image.id] = image.hash;
      }
    }
    var golden = GoldenTestImages(
      deviceInfo: report.deviceInfo,
      goldenHashes: data,
      suiteName: report.suiteName,
      testName: report.name,
      testVersion: report.version,
    );

    await uploadImages(
      report,
      goldenOnly: true,
    );

    await uploadTextFile(
      [actualCollectionPath, name],
      json.encode(
        golden.toJson(),
      ),
    );
  }

  /// Reader to read a golden image from Cloud Storage.
  Future<Uint8List> testImageReader({
    @required TestDeviceInfo deviceInfo,
    @required String imageId,
    String suiteName,
    @required String testName,
    int testVersion,
  }) async {
    GoldenTestImages golden;
    if (_currentGoldenTestImages?.testName == testName &&
        _currentGoldenTestImages?.suiteName == suiteName &&
        _currentGoldenTestImages?.deviceInfo?.orientation ==
            deviceInfo.orientation &&
        _currentGoldenTestImages?.deviceInfo?.os == deviceInfo.os &&
        _currentGoldenTestImages?.deviceInfo?.pixels?.width ==
            deviceInfo?.pixels?.width &&
        _currentGoldenTestImages?.deviceInfo?.pixels?.height ==
            deviceInfo?.pixels?.height) {
      golden = _currentGoldenTestImages;
    } else {
      var actualCollectionPath = '${testCollectionPath ?? 'tests'}/goldens';

      var suitePrefix = suiteName?.isNotEmpty == true ? '${suiteName}_' : '';
      var name =
          '${suitePrefix}${testName}_${deviceInfo.os}_${deviceInfo.orientation}_${deviceInfo.pixels.width}x${deviceInfo.pixels.height}.json';

      var data = await downloadTextFile([actualCollectionPath, name]);

      var goldenJson = json.decode(data);
      golden = GoldenTestImages.fromDynamic(goldenJson);
    }

    Uint8List image;
    if (golden != null) {
      var hash = golden.goldenHashes[imageId];
      image = await downloadImage(hash);
    }

    return image;
  }

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

      var snapshot = await downloadTextFile([
        actualCollectionPath,
        'all_tests.json',
      ]);
      var tests = json.decode(snapshot);

      tests.forEach((id, data) {
        var activeVersion = JsonClass.parseInt(data['activeVersion']);
        var pTest = PendingTest(
          loader: AsyncTestLoader(({bool ignoreImages}) async {
            var testData = await downloadTextFile([
              actualCollectionPath,
              '${id}_$activeVersion.json',
            ]);

            var realData = json.decode(testData);
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
              suiteName: realData['suiteName'],
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

    await uploadTextFile([
      actualCollectionPath,
      report.name,
      report.version.toString(),
      '${report.deviceInfo.deviceSignature}_${report.startTime.millisecondsSinceEpoch}.json',
    ], json.encode(report.toJson(false)));

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

      var id =
          (test.suiteName?.isNotEmpty == true ? '${test.suiteName}__' : '') +
              test.name;

      var tests = <String, dynamic>{};
      try {
        var snapshot = await downloadTextFile(
          [actualCollectionPath, 'all_tests.json'],
        );
        tests = json.decode(snapshot);
      } catch (e) {
        // no-op; assume the file just doesn't exist
      }

      var version = (test.version ?? 0) + 1;
      tests[id] = {
        'activeVersion': version,
        'name': test.name,
        'numSteps': test.steps.length,
        'suiteName': test.suiteName,
      };
      await uploadTextFile(
        [
          actualCollectionPath,
          'all_tests.json',
        ],
        json.encode(tests),
      );

      var testData = test
          .copyWith(
            timestamp: DateTime.now(),
            version: version,
          )
          .toJson();

      await uploadTextFile(
        [
          actualCollectionPath,
          '${id}_$version.json',
        ],
        json.encode(testData),
      );

      result = true;
    } catch (e, stack) {
      _logger.severe('Error writing test', e, stack);
    }
    return result;
  }

  /// Uploads the images from the given [report].  If [goldenOnly] is [true]
  /// then only the images marked as golden compatible will be uploaded.
  Future<void> uploadImages(
    TestReport report, {
    bool goldenOnly = false,
  }) async {
    if (!kIsWeb) {
      var images = goldenOnly == true
          ? report.images.where((image) => image.goldenCompatible == true)
          : report.images;

      for (var image in images) {
        var actualImagePath = imagePath ?? 'images';
        var ref =
            storage.ref().child(actualImagePath).child('${image.hash}.png');
        var uploadTask = ref.putData(
          image.image,
          StorageMetadata(contentType: 'image/png'),
        );

        var lastProgress = -10;
        uploadTask.events.listen((event) {
          var progress =
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

  /// Uploads a text file to Cloud Firestore.  If the [gzipData] is set to
  /// [true] then the data will be encoded via GZIP before transmission and the
  /// encoding will be set to 'gzip', otherwise the data will be sent with
  /// vanilla UTF8 encoding and the encoding will be set to 'utf8'.
  ///
  /// The [children] must contain one or more path elements to the location of
  /// the text file.
  Future<void> uploadTextFile(
    List<String> children,
    String data, {
    bool gzipData = true,
  }) async {
    var ref = storage.ref();
    for (var child in children) {
      ref = ref.child(child);
    }

    var bytes = utf8.encode(data);
    if (gzipData == true) {
      bytes = gzip.encoder.convert(bytes);
    }
    var task = await ref
        .putData(
          Uint8List.fromList(bytes),
          StorageMetadata(
            contentEncoding: gzipData == true ? 'gzip' : 'utf8',
            contentType: 'application/json',
          ),
        )
        .onComplete;
    if (task.error != null) {
      throw Exception('Error writing: $children -- code: ${task.error}');
    }
  }
}
