import 'dart:ui';
import 'package:flutter/material.dart';

class RecommendedLook {
  final String title;
  final List<String> imageUrls; // expect 4 urls

  const RecommendedLook({
    required this.title,
    required this.imageUrls,
  });
}

class RecommendedLayeredGridSliver extends StatelessWidget {
  final List<RecommendedLook> looks;

  const RecommendedLayeredGridSliver({
    super.key,
    required this.looks,
  });

  @override
  Widget build(BuildContext context) {
    // hard limit to 6 (as you asked)
    final items = looks.take(6).toList();

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.7,
        ),
        delegate: SliverChildBuilderDelegate(
              (context, index) => _LayeredLookCard(look: items[index]),
          childCount: items.length,
        ),
      ),
    );
  }
}

class _LayeredLookCard extends StatelessWidget {
  final RecommendedLook look;

  const _LayeredLookCard({required this.look});

  @override
  Widget build(BuildContext context) {
    final urls = look.imageUrls.length >= 4
        ? look.imageUrls.take(4).toList()
        : [
      ...look.imageUrls,
      ...List.filled(4 - look.imageUrls.length, look.imageUrls.isNotEmpty ? look.imageUrls.last : ""),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          // base background
          Positioned.fill(
            child: Container(
              color: Colors.white,
            ),
          ),

          // layered images (4)
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Stack(
                children: [
                  _layerImage(urls[3], dx: 18, dy: 18, blur: 0.0),
                  _layerImage(urls[2], dx: 12, dy: 12, blur: 0.0),
                  _layerImage(urls[1], dx: 6, dy: 6, blur: 0.0),
                  _layerImage(urls[0], dx: 0, dy: 0, blur: 0.0),
                ],
              ),
            ),
          ),

          // bottom gradient + title
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.45)],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Text(
              look.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _layerImage(String url, {required double dx, required double dy, required double blur}) {
    final radius = BorderRadius.circular(16);

    return Positioned(
      left: dx,
      top: dy,
      right: 0,
      bottom: 0,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned.fill(
              child: url.isEmpty
                  ? Container(color: Colors.black.withOpacity(0.06))
                  : Image.network(url, fit: BoxFit.cover),
            ),

            // subtle glass highlight on top images
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: radius,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                    child: Container(
                      color: Colors.white.withOpacity(0.04),
                    ),
                  ),
                ),
              ),
            ),

            // thin border so layers read cleanly
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: Colors.white.withOpacity(0.35), width: 1),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
