import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../data/wardrobe_store.dart';
import '../data/wardrobe_item.dart';

class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({super.key});

  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  String _selectedCategory = "all";
  late Future<List<WardrobeItem>> _itemsFuture;

  StreamSubscription<BoxEvent>? _watchSub;

  final List<_WardrobeCategory> _categories = const [
    _WardrobeCategory(keyName: "all", label: "All"),
    _WardrobeCategory(keyName: "tshirts", label: "T-Shirts"),
    _WardrobeCategory(keyName: "pants", label: "Pants"),
    _WardrobeCategory(keyName: "outerwear", label: "Outerwear"),
    _WardrobeCategory(keyName: "shoes", label: "Shoes"),
  ];

  @override
  void initState() {
    super.initState();
    _itemsFuture = WardrobeStore.getByCategory(_selectedCategory);

    // ✅ Live reload on Hive changes
    final box = Hive.box("wardrobe_items");
    _watchSub = box.watch().listen((_) {
      if (!mounted) return;
      setState(() {
        _itemsFuture = WardrobeStore.getByCategory(_selectedCategory);
      });
    });
  }

  @override
  void dispose() {
    _watchSub?.cancel();
    super.dispose();
  }

  void _selectCategory(String keyName) {
    if (_selectedCategory == keyName) return;
    setState(() {
      _selectedCategory = keyName;
      _itemsFuture = WardrobeStore.getByCategory(_selectedCategory);
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _itemsFuture = WardrobeStore.getByCategory(_selectedCategory);
    });

    await _itemsFuture;
    await Future.delayed(const Duration(milliseconds: 200));
  }

  void _openItemSheet(WardrobeItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.25),
      builder: (_) {
        final h = MediaQuery.of(context).size.height;
        return _WardrobeItemSheet(
          item: item,
          height: h * 0.78,
          onDeleted: () {
            if (!context.mounted) return;
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('"${item.label}" deleted'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFFFF8E1),
              Colors.white,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.45],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _refresh,
            color: Colors.black87,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 16)),

                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverToBoxAdapter(child: _buildTitle()),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 18)),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: _buildCategoryRow(),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 18)),

                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverToBoxAdapter(child: _buildDivider()),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 18)),

                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverToBoxAdapter(
                    child: FutureBuilder<List<WardrobeItem>>(
                      future: _itemsFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return _buildLoadingGrid();
                        }

                        if (snapshot.hasError) {
                          return _buildErrorState(snapshot.error.toString());
                        }

                        final items = snapshot.data ?? [];
                        if (items.isEmpty) return _buildEmptyState();

                        return _buildGrid(items);
                      },
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return const Text(
      "My wardrobe",
      style: TextStyle(
        fontSize: 42,
        fontWeight: FontWeight.w900,
        height: 1.0,
        letterSpacing: -1.5,
        color: Color(0xFF1A1A1A),
      ),
    );
  }

  Widget _buildDivider() {
    return Center(
      child: Container(
        width: double.infinity,
        height: 1.5,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              Colors.black.withOpacity(0.15),
              Colors.transparent,
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _buildCategoryRow() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final cat = _categories[i];
          final selected = cat.keyName == _selectedCategory;
          return GestureDetector(
            onTap: () => _selectCategory(cat.keyName),
            child: _GlassChip(text: cat.label, selected: selected),
          );
        },
      ),
    );
  }

  Widget _buildGrid(List<WardrobeItem> items) {
    return GridView.builder(
      itemCount: items.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.78,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return _WardrobeCard(
          item: item,
          onTap: () => _openItemSheet(item),
        );
      },
    );
  }

  Widget _buildLoadingGrid() {
    return GridView.builder(
      itemCount: 6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.78,
      ),
      itemBuilder: (context, index) => const _SkeletonCard(),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: _GlassPanel(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(Icons.checkroom, color: Colors.grey.shade700, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  "No items yet.\nAdd clothes from the camera screen and they’ll appear here.",
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.25,
                    color: Colors.black.withOpacity(0.75),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: _GlassPanel(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.error_outline, color: Colors.black87, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  "Wardrobe failed to load.\n$message",
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.25,
                    color: Colors.black.withOpacity(0.75),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WardrobeCategory {
  final String keyName;
  final String label;
  const _WardrobeCategory({required this.keyName, required this.label});
}

class _GlassChip extends StatelessWidget {
  final String text;
  final bool selected;

  const _GlassChip({required this.text, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: selected
            ? LinearGradient(
          colors: [
            Colors.grey.shade700.withOpacity(0.30),
            Colors.grey.shade500.withOpacity(0.20),
          ],
        )
            : LinearGradient(
          colors: [
            Colors.grey.shade400.withOpacity(0.16),
            Colors.grey.shade300.withOpacity(0.10),
          ],
        ),
        border: Border.all(
          color: selected ? Colors.white.withOpacity(0.65) : Colors.white.withOpacity(0.45),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: -2,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );
  }
}

class _WardrobeCard extends StatelessWidget {
  final WardrobeItem item;
  final VoidCallback onTap;

  const _WardrobeCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: _GlassPanel(
        radius: 26,
        plain: true,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: double.infinity,
                    color: Colors.white.withOpacity(0.22),
                    child: Image.file(
                      File(item.imagePath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                        child: Icon(Icons.image_not_supported_outlined,
                            size: 28, color: Colors.grey.shade700),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _WardrobeItemSheet extends StatelessWidget {
  final WardrobeItem item;
  final double height;
  final VoidCallback onDeleted;

  const _WardrobeItemSheet({
    required this.item,
    required this.height,
    required this.onDeleted,
  });

  String _prettyCategory(String c) {
    switch (c) {
      case "tshirts":
        return "T-Shirts";
      case "pants":
        return "Pants";
      case "outerwear":
        return "Outerwear";
      case "shoes":
        return "Shoes";
      default:
        return c;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: height,
        width: double.infinity,
        margin: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(26),
            topRight: Radius.circular(26),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(26),
            topRight: Radius.circular(26),
          ),
          child: SafeArea(
            bottom: true,
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, 12, 18, 8 + bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ✅ This block is what prevents overflows:
                  // It ALWAYS keeps the image square, but shrinks it if vertical space is tight.
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final size = math.min(c.maxWidth, c.maxHeight);
                        return Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: SizedBox(
                              width: size,
                              height: size,
                              child: Container(
                                color: Colors.grey.shade100,
                                child: Image.file(
                                  File(item.imagePath),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Center(
                                    child: Icon(
                                      Icons.image_not_supported_outlined,
                                      size: 34,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );

                      },
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),

                  const SizedBox(height: 10),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _metaChip(Icons.category_outlined, _prettyCategory(item.category)),
                      if (item.dominantColorHex.isNotEmpty)
                        _metaChip(Icons.palette_outlined, item.dominantColorHex),
                    ],
                  ),

                  const SizedBox(height: 14),

                  GestureDetector(
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        barrierColor: Colors.black.withOpacity(0.25),
                        builder: (_) => AlertDialog(
                          title: const Text("Delete item?"),
                          content: Text('Delete "${item.label}" from wardrobe?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text("Cancel"),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text("Delete"),
                            ),
                          ],
                        ),
                      );

                      if (ok != true) return;

                      await WardrobeStore.deleteItem(item);
                      onDeleted();
                    },
                    child: _GlassPanel(
                      radius: 22,
                      plain: false,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          color: Colors.red.withOpacity(0.10),
                          border: Border.all(
                            color: Colors.red.withOpacity(0.18),
                            width: 1.0,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.delete_outline, color: Colors.red.shade700),
                              const SizedBox(width: 8),
                              Text(
                                "Delete item",
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.grey.shade100,
        border: Border.all(
          color: Colors.black.withOpacity(0.08),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.black.withOpacity(0.72)),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 13.2,
              fontWeight: FontWeight.w700,
              color: Colors.black.withOpacity(0.78),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  final bool plain;

  const _GlassPanel({
    required this.child,
    this.radius = 25,
    this.plain = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            spreadRadius: -2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: plain
                    ? [
                  Colors.white.withOpacity(0.25),
                  Colors.white.withOpacity(0.15),
                  Colors.white.withOpacity(0.05),
                ]
                    : [
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
            child: child,
          ),
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      radius: 26,
      plain: true,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              height: 14,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.22),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 12,
              width: 110,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

