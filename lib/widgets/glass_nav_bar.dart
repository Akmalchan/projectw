import 'dart:ui';
import 'package:flutter/material.dart';

class GlassNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const GlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double screenWidth = constraints.maxWidth;
        final double horizontalPadding = (screenWidth * 0.19).clamp(60.0, 140.0);

        final double navWidth = screenWidth - (horizontalPadding * 2);

        // FIX 1: Subtract the border width (1.5 * 2 = 3.0) from the total width
        // so our bubble math perfectly matches the Row's layout.
        final double innerWidth = navWidth - 3.0;
        final double itemWidth = innerWidth / 3;

        final double navHeight = (screenWidth * 0.21).clamp(65.0, 90.0);
        final double bubbleSize = navHeight * 0.8;
        final double iconSize = navHeight * 0.38;

        return Padding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 30),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(50),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 20,
                  spreadRadius: -2,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(50),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  height: navHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(50),
                    // NEW: A subtle grey gradient for the sleek monochrome look
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.grey.shade600.withOpacity(0.15),
                        Colors.grey.shade400.withOpacity(0.10),
                        Colors.white.withOpacity(0.05),
                      ],
                      stops: const [0.1, 0.5, 0.9],
                    ),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Stack(
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        // FIX 2: Anchor top and bottom to 0 to force perfect vertical centering
                        top: 0,
                        bottom: 0,
                        left: itemWidth * currentIndex,
                        child: Container(
                          width: itemWidth,
                          alignment: Alignment.center,
                          child: Container(
                            width: bubbleSize,
                            height: bubbleSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              // NEW: A slightly frostier white for the active bubble
                              color: Colors.white.withOpacity(0.35),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.8),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Wrapped in Positioned.fill to guarantee it perfectly matches inner dimensions
                      Positioned.fill(
                        child: Row(
                          children: [
                            _navItem(Icons.home, 0, iconSize),
                            _navItem(Icons.camera_alt, 1, iconSize),
                            _navItem(Icons.checkroom, 2, iconSize),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _navItem(IconData icon, int index, double iconSize) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(index),
        child: Center(
          child: Icon(
            icon,
            size: iconSize,
            color: Colors.black87, // Kept stark black for high contrast
          ),
        ),
      ),
    );
  }
}