import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_background_remover/image_background_remover.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class BgCutoutCache {
  // Dedupe: one Future per key, so multiple widgets share it.
  static final Map<String, Future<Uint8List>> _inFlight = {};

  // Serialize: ensure removeBg runs one at a time (prevents ORT isolate races).
  static Future<void> _queue = Future.value();

  static Future<Uint8List> _loadBytes(ImageProvider provider) async {
    if (provider is AssetImage) {
      final bd = await rootBundle.load(provider.assetName);
      return bd.buffer.asUint8List();
    }
    if (provider is FileImage) {
      return File(provider.file.path).readAsBytes();
    }
    throw UnsupportedError('BgCutoutCache supports AssetImage and FileImage only (for now).');
  }

  static Future<File> _cacheFile(String key) async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/cutouts');
    if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
    return File('${cacheDir.path}/$key.png');
  }

  static Future<Uint8List> getOrCreatePng({
    required String cacheKey,
    required ImageProvider source,
  }) {
    // If already generating, return same Future.
    final existing = _inFlight[cacheKey];
    if (existing != null) return existing;

    final future = _getOrCreateInternal(cacheKey: cacheKey, source: source);
    _inFlight[cacheKey] = future;

    // Ensure we remove from map when done (success or fail).
    future.whenComplete(() => _inFlight.remove(cacheKey));

    return future;
  }

  static Future<Uint8List> _getOrCreateInternal({
    required String cacheKey,
    required ImageProvider source,
  }) async {
    final f = await _cacheFile(cacheKey);

    if (await f.exists()) {
      return f.readAsBytes();
    }

    // Load original bytes
    final srcBytes = await _loadBytes(source);

    // Serialize removeBg calls to avoid ORT isolate/session races.
    Uint8List resultBytes = Uint8List(0);

    await (_queue = _queue.then((_) async {
      // Another check (someone could have produced it while we waited in queue)
      if (await f.exists()) {
        resultBytes = await f.readAsBytes();
        return;
      }

      // This can still throw; we handle it.
      final ui.Image uiImage = await BackgroundRemover.instance.removeBg(
        srcBytes,
        threshold: 0.5,
        smoothMask: true,
        enhanceEdges: true,
      );

      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('Failed to encode cutout PNG.');
      }

      resultBytes = byteData.buffer.asUint8List();
      await f.writeAsBytes(resultBytes, flush: true);
    }).catchError((e, st) async {
      // If ONNX crashes/throws, do NOT poison cache; just rethrow.
      debugPrint('BgCutoutCache error for $cacheKey: $e');
      throw e!;
    }));

    return resultBytes;
  }
}

