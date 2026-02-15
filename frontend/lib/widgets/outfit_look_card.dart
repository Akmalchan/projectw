import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../utils/bg_cutout_cache.dart';

class OutfitLookCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<ImageProvider> layers;
  final VoidCallback? onTap;

  /// Turns on background cleaning (cutout).
  final bool whiteKeyBackground;

  const OutfitLookCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.layers,
    this.onTap,
    this.whiteKeyBackground = false,
  });

  @override
  Widget build(BuildContext context) {
    // ✅ IMPORTANT: include the actual images in the cache identity
    final sig = _signatureFromProviders(layers);
    final cachePrefix =
        '${title.replaceAll(' ', '_').toLowerCase()}_$sig'; // stable, changes when images change

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 230,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white,
          border: Border.all(color: Colors.black.withOpacity(0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CollagePreview(
                  images: layers,
                  whiteKeyBackground: whiteKeyBackground,
                  cachePrefix: cachePrefix,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style:
                      const TextStyle(color: Colors.black54, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollagePreview extends StatelessWidget {
  final List<ImageProvider> images;
  final bool whiteKeyBackground;
  final String cachePrefix;

  const _CollagePreview({
    required this.images,
    required this.whiteKeyBackground,
    required this.cachePrefix,
  });

  @override
  Widget build(BuildContext context) {
    final jacket = images.isNotEmpty ? images[0] : null;
    final shirt  = images.length > 1 ? images[1] : null;
    final pants  = images.length > 2 ? images[2] : null;
    final shoe   = images.length > 3 ? images[3] : null;

    Widget tile(
        ImageProvider p, {
          required String cacheKey,
          double zoom = 1.0,
          BoxFit fit = BoxFit.contain,
          Alignment alignment = Alignment.center,
        }) {
      final base = whiteKeyBackground
          ? CutoutImage(source: p, cacheKey: cacheKey)
          : Image(image: p, fit: fit, filterQuality: FilterQuality.low);

      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: Colors.transparent,
          child: Transform.scale(
            scale: zoom,
            child: Align(alignment: alignment, child: base),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        return Container(
          color: const Color(0xFFF6F6F6),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // 1) Pants: bottom-most, lower-right, fills most free space
              if (pants != null)
                Positioned(
                  left: w * 0.38,
                  top:  h * 0.28,
                  width: w * 0.66,
                  height: h * 0.78,
                  child: tile(
                    pants,
                    cacheKey: '${cachePrefix}_pants',
                    zoom: 1.10,
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomCenter,
                  ),
                ),

              // 2) Shirt: behind jacket, shifted slightly right/up
              if (shirt != null)
                Positioned(
                  left: w * 0.34,
                  top:  h * 0.06,
                  width: w * 0.56,
                  height: h * 0.52,
                  child: tile(
                    shirt,
                    cacheKey: '${cachePrefix}_shirt',
                    zoom: 1.08,
                    fit: BoxFit.contain,
                    alignment: Alignment.topCenter,
                  ),
                ),

              // 3) Sneaker: bottom-left, sits above pants
              if (shoe != null)
                Positioned(
                  left: w * 0.08,
                  top:  h * 0.64,
                  width: w * 0.44,
                  height: h * 0.32,
                  child: tile(
                    shoe,
                    cacheKey: '${cachePrefix}_shoe',
                    zoom: 1.15,
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomLeft,
                  ),
                ),

              // 4) Jacket: highest in hierarchy, ~40% area, left biased
              if (jacket != null)
                Positioned(
                  left: w * 0.06,
                  top:  h * 0.06,
                  width: w * 0.62,
                  height: h * 0.58,
                  child: tile(
                    jacket,
                    cacheKey: '${cachePrefix}_jacket',
                    zoom: 1.12,
                    fit: BoxFit.contain,
                    alignment: Alignment.topLeft,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

}

/// Shows a background-removed PNG (cached).
/// While generating, it shows the original image as a fallback.
class CutoutImage extends StatefulWidget {
  final ImageProvider source;
  final String cacheKey;

  const CutoutImage({
    super.key,
    required this.source,
    required this.cacheKey,
  });

  @override
  State<CutoutImage> createState() => _CutoutImageState();
}

class _CutoutImageState extends State<CutoutImage> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = BgCutoutCache.getOrCreatePng(
      cacheKey: widget.cacheKey,
      source: widget.source,
    );
  }

  @override
  void didUpdateWidget(covariant CutoutImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.source != widget.source) {
      _future = BgCutoutCache.getOrCreatePng(
        cacheKey: widget.cacheKey,
        source: widget.source,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasData) {
          return Image.memory(
            snap.data!,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.low,
          );
        }

        // fallback while processing (or if it fails)
        return Image(
          image: widget.source,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.low,
        );
      },
    );
  }
}

/// --- Cache key helpers ---
/// We build a stable signature from the ImageProviders.
/// If images change, signature changes => new cache keys => new cutouts.
String _signatureFromProviders(List<ImageProvider> providers) {
  final ids = providers.map(_providerId).toList(growable: false);
  final h = Object.hashAll(ids);
  // keep it short-ish but stable:
  return h.toUnsigned(32).toRadixString(16);
}

String _providerId(ImageProvider p) {
  if (p is AssetImage) return 'asset:${p.assetName}';
  if (p is FileImage) return 'file:${p.file.path}';
  if (p is NetworkImage) return 'net:${p.url}';
  return 'other:${p.toString()}';
}



