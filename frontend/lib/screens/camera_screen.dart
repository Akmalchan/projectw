import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  static const _keyChannel = MethodChannel("sfhacks/keys");

  CameraController? _controller;
  Interpreter? _interpreter;

  bool _busy = false;
  String _hud = "Starting…";

  int _inW = 640;
  int _inH = 640;
  bool _isNCHW = true;

  bool _printedBoxDebug = false;

  @override
  void initState() {
    super.initState();
    _setupKeyListener();
    _init();
  }

  void _setupKeyListener() {
    _keyChannel.setMethodCallHandler((call) async {
      if (call.method == "volume") {
        if (!_busy) await _takeAndProcess();
      }
    });
  }

  Future<void> _init() async {
    final modelData = await rootBundle.load('assets/models/yolov8n.tflite');
    _interpreter = Interpreter.fromBuffer(
      modelData.buffer.asUint8List(),
      options: InterpreterOptions()..threads = 4,
    );

    final inT = _interpreter!.getInputTensor(0);
    final outT = _interpreter!.getOutputTensor(0);

    debugPrint("MODEL INPUT shape=${inT.shape} type=${inT.type}");
    debugPrint("MODEL OUTPUT shape=${outT.shape} type=${outT.type}");

    final s = inT.shape;
    if (s.length == 4 && s[1] == 3) {
      _isNCHW = true;
      _inH = s[2];
      _inW = s[3];
    } else if (s.length == 4 && s[3] == 3) {
      _isNCHW = false;
      _inH = s[1];
      _inW = s[2];
    } else {
      throw UnsupportedError("Unsupported input shape: $s");
    }

    final front = widget.cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );

    _controller = CameraController(
      front,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await _controller!.initialize();
    if (!mounted) return;

    setState(() {
      _hud = "Ready. Capture.\nInput=${_isNCHW ? "NCHW" : "NHWC"} ${_inW}x${_inH}";
    });
  }

  Future<void> _takeAndProcess() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _interpreter == null) return;

    setState(() {
      _busy = true;
      _hud = "Capturing…";
    });

    try {
      final xfile = await c.takePicture();
      final jpgBytes = await xfile.readAsBytes();
      final full = img.decodeImage(jpgBytes);
      if (full == null) {
        setState(() => _hud = "Decode failed");
        return;
      }

      setState(() => _hud = "Running YOLO…");

      final det = _detectBestPerson(full);
      if (det == null) {
        setState(() => _hud = "No PERSON detected.");
        return;
      }

      // If crop ends up tiny (bad box), fallback to center crop
      img.Image crop;
      try {
        crop = _cropByRectSafe(full, det.rect, expand: 0.12);
      } catch (_) {
        crop = _fallbackCenterCrop(full);
      }

      // Ensure not blank: if very small, fallback
      if (crop.width < 30 || crop.height < 30) {
        crop = _fallbackCenterCrop(full);
      }

      final png = Uint8List.fromList(img.encodePng(crop));

      setState(() => _hud = "PERSON score=${det.score.toStringAsFixed(2)} ✅");
      if (!mounted) return;
      await _showPopup(png);
    } catch (e) {
      setState(() => _hud = "Error: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Output (1,84,8400) as [C,N].
  // Fix: handle normalized vs pixel coords.
  _Det? _detectBestPerson(img.Image full) {
    final resized = img.copyResize(full, width: _inW, height: _inH);

    final flat = _isNCHW ? _buildNCHW(resized) : _buildNHWC(resized);
    final input = _isNCHW
        ? flat.reshape([1, 3, _inH, _inW])
        : flat.reshape([1, _inH, _inW, 3]);

    final outputFlat = Float32List(84 * 8400);
    final output = outputFlat.reshape([1, 84, 8400]);

    _interpreter!.runForMultipleInputs([input], {0: output});

    const int n = 8400;
    const int personCls = 0;
    const double scoreThresh = 0.25;

    double bestScore = 0;
    _RectF? bestRect;

    // We'll also keep the raw best box for debug
    double bestX = 0, bestY = 0, bestW = 0, bestH = 0;

    for (int i = 0; i < n; i++) {
      final x = output[0][0][i];
      final y = output[0][1][i];
      final w = output[0][2][i];
      final h = output[0][3][i];

      final score = output[0][4 + personCls][i];
      if (score < scoreThresh) continue;

      if (score > bestScore) {
        bestScore = score;
        bestX = x; bestY = y; bestW = w; bestH = h;

        // Convert center->corners in model space
        double left = x - w / 2.0;
        double top = y - h / 2.0;
        double right = x + w / 2.0;
        double bottom = y + h / 2.0;

        // Detect normalized coords (common in TFLite exports)
        // If values are mostly <= 1.5, treat as normalized (0..1)
        final looksNormalized = (x.abs() <= 1.5 && y.abs() <= 1.5 && w.abs() <= 1.5 && h.abs() <= 1.5);

        if (looksNormalized) {
          // Normalize space -> original pixels
          bestRect = _RectF(
            left: left * full.width,
            top: top * full.height,
            right: right * full.width,
            bottom: bottom * full.height,
          );
        } else {
          // Pixel space in model -> scale to original
          final sx = full.width / _inW;
          final sy = full.height / _inH;
          bestRect = _RectF(
            left: left * sx,
            top: top * sy,
            right: right * sx,
            bottom: bottom * sy,
          );
        }
      }
    }

    if (bestRect == null) return null;

    if (!_printedBoxDebug) {
      _printedBoxDebug = true;
      debugPrint("BEST raw box: x=$bestX y=$bestY w=$bestW h=$bestH score=$bestScore");
      debugPrint("BEST rect px: l=${bestRect.left} t=${bestRect.top} r=${bestRect.right} b=${bestRect.bottom}");
    }

    return _Det(rect: bestRect, score: bestScore);
  }

  Float32List _buildNCHW(img.Image im) {
    final out = Float32List(3 * _inH * _inW);
    final rBase = 0;
    final gBase = _inH * _inW;
    final bBase = 2 * _inH * _inW;

    for (int y = 0; y < _inH; y++) {
      for (int x = 0; x < _inW; x++) {
        final p = im.getPixel(x, y);
        final pos = y * _inW + x;
        out[rBase + pos] = p.r / 255.0;
        out[gBase + pos] = p.g / 255.0;
        out[bBase + pos] = p.b / 255.0;
      }
    }
    return out;
  }

  Float32List _buildNHWC(img.Image im) {
    final out = Float32List(_inH * _inW * 3);
    int idx = 0;
    for (int y = 0; y < _inH; y++) {
      for (int x = 0; x < _inW; x++) {
        final p = im.getPixel(x, y);
        out[idx++] = p.r / 255.0;
        out[idx++] = p.g / 255.0;
        out[idx++] = p.b / 255.0;
      }
    }
    return out;
  }

  img.Image _cropByRectSafe(img.Image full, _RectF r, {double expand = 0.0}) {
    final W = full.width;
    final H = full.height;

    double l = r.left;
    double t = r.top;
    double rr = r.right;
    double bb = r.bottom;

    // Fix inverted / invalid
    if (rr < l) { final tmp = l; l = rr; rr = tmp; }
    if (bb < t) { final tmp = t; t = bb; bb = tmp; }

    final rectW = (rr - l).abs();
    final rectH = (bb - t).abs();

    // Expand box
    final ex = rectW * expand;
    final ey = rectH * expand;

    int x = (l - ex).round();
    int y = (t - ey).round();
    int w = (rectW + 2 * ex).round();
    int h = (rectH + 2 * ey).round();

    // Clamp
    x = x.clamp(0, W - 1);
    y = y.clamp(0, H - 1);
    w = math.max(1, math.min(w, W - x));
    h = math.max(1, math.min(h, H - y));

    return img.copyCrop(full, x: x, y: y, width: w, height: h);
  }

  img.Image _fallbackCenterCrop(img.Image full) {
    final w = full.width;
    final h = full.height;

    final cw = (w * 0.80).round();
    final ch = (h * 0.90).round();
    final x = ((w - cw) / 2).round();
    final y = (h * 0.05).round();

    final safeX = x.clamp(0, w - 1);
    final safeY = y.clamp(0, h - 1);
    final safeW = math.min(cw, w - safeX);
    final safeH = math.min(ch, h - safeY);

    return img.copyCrop(full, x: safeX, y: safeY, width: safeW, height: safeH);
  }

  Future<void> _showPopup(Uint8List pngBytes) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Crop result"),
        content: Image.memory(pngBytes),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK")),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _interpreter?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(c),
          Positioned(
            top: 48,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_hud, style: const TextStyle(color: Colors.white)),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomInset + 16,
            child: ElevatedButton(
              onPressed: _busy ? null : _takeAndProcess,
              child: Text(_busy ? "Processing…" : "Capture"),
            ),
          ),
        ],
      ),
    );
  }
}

class _RectF {
  final double left, top, right, bottom;
  _RectF({required this.left, required this.top, required this.right, required this.bottom});
}

class _Det {
  final _RectF rect;
  final double score;
  _Det({required this.rect, required this.score});
}
