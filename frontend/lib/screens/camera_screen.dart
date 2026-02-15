import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

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

  // --- LOGIC METHODS (Exactly from your file) ---

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

      img.Image crop;
      try {
        crop = _cropByRectSafe(full, det.rect, expand: 0.12);
      } catch (_) {
        crop = _fallbackCenterCrop(full);
      }

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

  _Det? _detectBestPerson(img.Image full) {
    final resized = img.copyResize(full, width: _inW, height: _inH);
    final flat = _isNCHW ? _buildNCHW(resized) : _buildNHWC(resized);
    final input = _isNCHW ? flat.reshape([1, 3, _inH, _inW]) : flat.reshape([1, _inH, _inW, 3]);

    final outputFlat = Float32List(84 * 8400);
    final output = outputFlat.reshape([1, 84, 8400]);

    _interpreter!.runForMultipleInputs([input], {0: output});

    const int n = 8400;
    const int personCls = 0;
    const double scoreThresh = 0.25;

    double bestScore = 0;
    _RectF? bestRect;

    for (int i = 0; i < n; i++) {
      final x = output[0][0][i];
      final y = output[0][1][i];
      final w = output[0][2][i];
      final h = output[0][3][i];
      final score = output[0][4 + personCls][i];

      if (score < scoreThresh) continue;

      if (score > bestScore) {
        bestScore = score;
        double left = x - w / 2.0;
        double top = y - h / 2.0;
        double right = x + w / 2.0;
        double bottom = y + h / 2.0;

        final looksNormalized = (x.abs() <= 1.5 && y.abs() <= 1.5 && w.abs() <= 1.5 && h.abs() <= 1.5);

        if (looksNormalized) {
          bestRect = _RectF(
            left: left * full.width,
            top: top * full.height,
            right: right * full.width,
            bottom: bottom * full.height,
          );
        } else {
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
    return bestRect == null ? null : _Det(rect: bestRect, score: bestScore);
  }

  Float32List _buildNCHW(img.Image im) {
    final out = Float32List(3 * _inH * _inW);
    final gBase = _inH * _inW;
    final bBase = 2 * _inH * _inW;
    for (int y = 0; y < _inH; y++) {
      for (int x = 0; x < _inW; x++) {
        final p = im.getPixel(x, y);
        final pos = y * _inW + x;
        out[pos] = p.r / 255.0;
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
    double l = r.left, t = r.top, rr = r.right, bb = r.bottom;
    if (rr < l) { final tmp = l; l = rr; rr = tmp; }
    if (bb < t) { final tmp = t; t = bb; bb = tmp; }
    final rectW = (rr - l).abs();
    final rectH = (bb - t).abs();
    final ex = rectW * expand;
    final ey = rectH * expand;
    int x = (l - ex).round().clamp(0, full.width - 1);
    int y = (t - ey).round().clamp(0, full.height - 1);
    int w = (rectW + 2 * ex).round().clamp(1, full.width - x);
    int h = (rectH + 2 * ey).round().clamp(1, full.height - y);
    return img.copyCrop(full, x: x, y: y, width: w, height: h);
  }

  img.Image _fallbackCenterCrop(img.Image full) {
    final w = full.width, h = full.height;
    final cw = (w * 0.80).round(), ch = (h * 0.90).round();
    final x = ((w - cw) / 2).round().clamp(0, w - 1);
    final y = (h * 0.05).round().clamp(0, h - 1);
    return img.copyCrop(full, x: x, y: y, width: math.min(cw, w - x), height: math.min(ch, h - y));
  }

  Future<void> _showPopup(Uint8List pngBytes) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Crop result", style: TextStyle(fontWeight: FontWeight.bold)),
        content: ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.memory(pngBytes)),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
      ),
    );
  }

  // --- UI BUILD METHODS ---

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.white)));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // 1. Camera Feed Window
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(50),
                bottomRight: Radius.circular(50),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AspectRatio(
                    aspectRatio: 1 / c.value.aspectRatio,
                    child: CameraPreview(c),
                  ),

                  // Top Log HUD
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 10,
                    left: 20,
                    right: 20,
                    child: _buildLogHUD(),
                  ),

                  // CAPTURE BUTTON: Relocated into the picture itself to clear the Nav Bar
                  Positioned(
                    bottom: 30,
                    left: 0,
                    right: 0,
                    child: Center(child: _buildClassicCaptureButton()),
                  ),
                ],
              ),
            ),
          ),

          // 2. TIGHTER PRISMATIC GAP (Fades to black at the bottom for system Nav Bar)
          Container(
            height: 160,
            width: double.infinity,
            color: Colors.black,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _buildPrismaticGlow(Colors.blueAccent, const Offset(-60, -20), size: 130),
                _buildPrismaticGlow(Colors.purpleAccent, const Offset(60, -20), size: 130),
                _buildPrismaticGlow(Colors.pinkAccent, const Offset(0, 0), size: 110),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogHUD() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Text(
            _hud,
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 11),
          ),
        ),
      ),
    );
  }

  Widget _buildPrismaticGlow(Color color, Offset offset, {double size = 150}) {
    return Transform.translate(
      offset: offset,
      child: Container(
        width: size,
        height: size * 0.7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.28),
              blurRadius: 70,
              spreadRadius: 10,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClassicCaptureButton() {
    return GestureDetector(
      onTap: _busy ? null : _takeAndProcess,
      child: Container(
        height: 76,
        width: 76,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 12)
            ]
        ),
        padding: const EdgeInsets.all(6),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          child: _busy
              ? const Center(child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3))
              : const Icon(Icons.auto_awesome, color: Colors.black, size: 30),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _interpreter?.close();
    super.dispose();
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