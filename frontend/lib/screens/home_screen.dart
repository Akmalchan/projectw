import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../widgets/outfit_look_card.dart';
import '../widgets/look_inspiration_sheet.dart';



class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class GeminiOutfitItem {
  final String title;
  final String subtitle;
  final String imageUrl; // or asset path, up to you

  const GeminiOutfitItem({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
  });
}

class GeminiSuggestion {
  final String message;
  final List<GeminiOutfitItem> items;

  const GeminiSuggestion({
    required this.message,
    required this.items,
  });
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // Typewriter logic
  final List<String> _phrases = [
    "outfit for college",
    "what to wear for a date",
    "party vibe outfit",
    "clean formal look",
  ];
  String _hintText = "";
  int _phraseIndex = 0;
  bool _showCursor = true;
  Timer? _cursorTimer;

  List<LookInspirationItem> _inspoItemsForLook(int index) {
    // You can change images/text freely. Using your existing assets to keep it simple.
    switch (index) {
      case 0:
        return const [
          LookInspirationItem(
            title: "Leather Jacket",
            subtitle: "Warm top layer idea",
            image: AssetImage("assets/wardrobe/jacket2.jpg"),
          ),
          LookInspirationItem(
            title: "Green Sweater",
            subtitle: "Weather-ready Top",
            image: AssetImage("assets/wardrobe/sweater2.jpg"),
          ),
          LookInspirationItem(
            title: "Golf Pants",
            subtitle: "Clean silhouette",
            image: AssetImage("assets/wardrobe/pants1.jpg"),
          ),
          LookInspirationItem(
            title: "Brown Boots",
            subtitle: "Formal",
            image: AssetImage("assets/wardrobe/boots2.jpg"),
          ),
        ];
      case 1:
        return const [
          LookInspirationItem(
            title: "Ferrari Jacket",
            subtitle: "History Classic",
            image: AssetImage("assets/wardrobe/jacket1.jpg"),
          ),
          LookInspirationItem(
            title: "Black Polo",
            subtitle: "Relaxed classic fit",
            image: AssetImage("assets/wardrobe/polo2.jpg"),
          ),
          LookInspirationItem(
            title: "Jeans",
            subtitle: "Fit for a jacket",
            image: AssetImage("assets/wardrobe/pants3.jpg"),
          ),
          LookInspirationItem(
            title: "Sneakers",
            subtitle: "Classic Vibe",
            image: AssetImage("assets/wardrobe/sneakers1.jpg"),
          ),
        ];
      case 2:
        return const [
          LookInspirationItem(
            title: "Smart Polo jacket",
            subtitle: "Sharp & classic layer",
            image: AssetImage("assets/wardrobe/jacket4.jpg"),
          ),
          LookInspirationItem(
            title: "Green Shirt",
            subtitle: "Minimal Spicy base",
            image: AssetImage("assets/wardrobe/shirt1.jpg"),
          ),
          LookInspirationItem(
            title: "Golf ants",
            subtitle: "Clean smart-casual",
            image: AssetImage("assets/wardrobe/pants1.jpg"),
          ),
          LookInspirationItem(
            title: "Sneakers",
            subtitle: "Classic Vibe",
            image: AssetImage("assets/wardrobe/sneakers1.jpg"),
          ),
        ];
      case 3:
        return const [
          LookInspirationItem(
            title: "Black Coat",
            subtitle: "Any weather piece",
            image: AssetImage("assets/wardrobe/coat1.jpg"),
          ),
          LookInspirationItem(
            title: "Black Polo",
            subtitle: "Classic Fit",
            image: AssetImage("assets/wardrobe/polo2.jpg"),
          ),
          LookInspirationItem(
            title: "Black Trousers",
            subtitle: "Best Option",
            image: AssetImage("assets/wardrobe/pants4.jpg"),
          ),
          LookInspirationItem(
            title: "Dark Boots",
            subtitle: "Optional for cold weather",
            image: AssetImage("assets/wardrobe/boots1.jpg"),
          ),
        ];
      default:
        return const [];
    }
  }

  void _showLookInspirationSheet(int lookIndex) {
    final items = _inspoItemsForLook(lookIndex);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (_) {
        return LookInspirationSheet(
          lookIndex: lookIndex,
          items: items,
        );
      },
    );
  }


  String _pinterestPromptForIndex(int index) {
    switch (index) {
      case 0:
        return "Suggest an outfit similar to Look 1 (warm layered style).";
      case 1:
        return "Suggest an outfit similar to Look 2 (streetwear / casual).";
      case 2:
        return "Suggest an outfit similar to Look 3 (smart casual).";
      case 3:
        return "Suggest an outfit similar to Look 4 (going-out / party).";
      default:
        return "Suggest an outfit inspired by this look.";
    }
  }


  @override
  void initState() {
    super.initState();
    _startAnimations();
  }

  void _startAnimations() {
    _cursorTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) setState(() => _showCursor = !_showCursor);
    });
    _animateTypewriter();
  }

  void _animateTypewriter() async {
    while (mounted) {
      final current = _phrases[_phraseIndex];

      for (int i = 0; i <= current.length; i++) {
        if (!mounted) return;
        setState(() => _hintText = current.substring(0, i));
        await Future.delayed(const Duration(milliseconds: 100));
      }

      await Future.delayed(const Duration(seconds: 2));

      for (int i = current.length; i >= 0; i--) {
        if (!mounted) return;
        setState(() => _hintText = current.substring(0, i));
        await Future.delayed(const Duration(milliseconds: 50));
      }

      _phraseIndex = (_phraseIndex + 1) % _phrases.length;
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  @override
  void dispose() {
    _cursorTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<GeminiSuggestion> _fetchGeminiSuggestion(String prompt) async {
    // TODO: replace with real HTTP call to your backend
    // Example: final res = await http.post(...)

    await Future.delayed(const Duration(milliseconds: 900));

    return const GeminiSuggestion(
      message: "It might be chilly today — go for warmer layers and darker tones.",
      items: [
        GeminiOutfitItem(
          title: "Warm Outerwear",
          subtitle: "Layer-friendly jacket",
          imageUrl: "https://picsum.photos/id/1011/400/300",
        ),
        GeminiOutfitItem(
          title: "Neutral Hoodie",
          subtitle: "Comfort + warmth",
          imageUrl: "https://picsum.photos/id/1025/400/300",
        ),
        GeminiOutfitItem(
          title: "Sneakers",
          subtitle: "All-day walking",
          imageUrl: "https://picsum.photos/id/103/400/300",
        ),
      ],
    );
  }

  void _showGeminiSheet({
    required String prompt,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: false, // IMPORTANT: allows flush-to-bottom
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (_) {
        return _GeminiBottomSheet(
          prompt: prompt,
          fetch: _fetchGeminiSuggestion,
        );
      },
    );
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // Optional: close keyboard
    _focusNode.unfocus();

    // Open sheet immediately; it will load inside.
    _showGeminiSheet(prompt: text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
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
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 40),
                    const Text(
                      "Hey!\nWhat's the occasion\nfor today?",
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                        letterSpacing: -1.5,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 35),
                  ]),
                ),
              ),

              SliverToBoxAdapter(child: _buildQuickOptions()),

              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 25),
                    _buildAITextField(),
                    const SizedBox(height: 40),
                    _buildSeparator(),
                    const SizedBox(height: 25),
                  ]),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.7,
                  ),
                  delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildPinterestCard(index),
                    childCount: 4,
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 150)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickOptions() {
    final List<String> options = ["College", "Date", "Party", "Formal"];
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          return InkWell(
            onTap: () {
              final text = "I need an outfit for ${options[i].toLowerCase()}";
              _controller.value = TextEditingValue(
                text: text,
                selection: TextSelection.collapsed(offset: text.length),
              );
              _focusNode.requestFocus();
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.black.withOpacity(0.05)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Center(
                child: Text(
                  options[i],
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAITextField() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: Colors.white.withOpacity(0.8),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              textAlignVertical: TextAlignVertical.center,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _handleSend(),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 18),
                hintText: "$_hintText${_showCursor ? '|' : ' '}",
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 16),
                prefixIcon: const Icon(Icons.auto_awesome, color: Colors.blueAccent),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded, color: Colors.black),
                  onPressed: _handleSend,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeparator() {
    return Row(
      children: [
        const Text(
          "Recommended",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.black.withOpacity(0.1), Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPinterestCard(int index) {
    final ImageProvider<Object> bgImage = switch (index) {
      0 => const AssetImage("assets/wardrobe/look1.jpg"),
      1 => const AssetImage("assets/wardrobe/look2.jpg"),
      2 => const AssetImage("assets/wardrobe/look3.jpg"),
      3 => const AssetImage("assets/wardrobe/look4.jpg"),
      _ => NetworkImage("https://picsum.photos/id/${index + 10}/400/600"),
    };

    return GestureDetector(
      onTap: () {
        _showLookInspirationSheet(index);
      },

      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Background image
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  image: DecorationImage(image: bgImage, fit: BoxFit.cover),
                ),
              ),
            ),

            // Optional: bottom gradient for readability
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 120,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.35),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom-right INFO button (still works independently)
            Positioned(
              right: 10,
              bottom: 10,
              child: GestureDetector(
                onTap: () {
                  // Optional: keep separate behavior for info
                  // If you want info to open the same sheet too, uncomment:
                  // _showGeminiSheet(prompt: "Explain this look and suggest similar items.");
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Icon(
                    Icons.info_outline,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }




  Widget _cardButton(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.3),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _GeminiBottomSheet extends StatefulWidget {
  final String prompt;
  final Future<GeminiSuggestion> Function(String prompt) fetch;

  const _GeminiBottomSheet({
    required this.prompt,
    required this.fetch,
  });

  @override
  State<_GeminiBottomSheet> createState() => _GeminiBottomSheetState();
}

class _GeminiBottomSheetState extends State<_GeminiBottomSheet> {
  late Future<GeminiSuggestion> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.fetch(widget.prompt);
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;

    return GestureDetector(
      onTap: () {},
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: height * 0.72,
          width: double.infinity,     // full width
          margin: EdgeInsets.zero,    // no side/bottom gaps
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(26),
              topRight: Radius.circular(26),
            ), // keep only top corners rounded
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
            child: FutureBuilder<GeminiSuggestion>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return _buildLoading();
                }
                if (snap.hasError) {
                  return _buildError();
                }
                final data = snap.data!;
                return _buildContent(data);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0x11000000),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 4),


          const SizedBox(height: 10),
          const Text(
            "Thinking…",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          const Text(
            "Generating outfit advice and picks.",
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const Spacer(),
          const Center(child: CircularProgressIndicator()),
          const Spacer(),
        ],
      ),
    );
  }


  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0x11000000),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 4),


          const SizedBox(height: 10),
          const Text(
            "Couldn’t load suggestions",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          const Text(
            "Please try again.",
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
        ],
      ),
    );
  }


  Widget _buildContent(GeminiSuggestion data) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const SizedBox(height: 6),
        Center(
          child: Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0x11000000),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
        const SizedBox(height: 14),

        Text(
          data.message,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          "Based on: “${widget.prompt}”",
          style: const TextStyle(fontSize: 13, color: Colors.black54),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),

        // ✅ Only keep the 3 look banners
        const SizedBox(height: 18),
        const Text(
          "3 looks",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),

        SizedBox(
          height: 340,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 3,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, idx) {
              final lookLayers = <List<ImageProvider>>[
                const [
                  AssetImage("assets/wardrobe/jacket4.jpg"),
                  AssetImage("assets/wardrobe/shirt1.jpg"),
                  AssetImage("assets/wardrobe/pants4.jpg"),
                  AssetImage("assets/wardrobe/sneakers1.jpg"),
                ],
                const [
                  AssetImage("assets/wardrobe/coat2.jpg"),
                  AssetImage("assets/wardrobe/sweater1.jpg"),
                  AssetImage("assets/wardrobe/pants1.jpg"),
                  AssetImage("assets/wardrobe/boots2.jpg"),
                ],
                const [
                  AssetImage("assets/wardrobe/jacket3.jpg"),
                  AssetImage("assets/wardrobe/sweater2.jpg"),
                  AssetImage("assets/wardrobe/pants3.jpg"),
                  AssetImage("assets/wardrobe/boots1.jpg"),
                ],
              ];

              return OutfitLookCard(
                title: "Look ${idx + 1}",
                subtitle: "Tap to view",
                layers: lookLayers[idx],
                whiteKeyBackground: true, // ✅ run cleaner for every look
                onTap: () {},
              );

            },
          ),
        ),
      ],
    );
  }




  Widget _itemCard(GeminiOutfitItem item) {
    return InkWell(
      onTap: () {
        // TODO: handle user selecting item
        // Example: add to outfit, open detail, etc.
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 220,
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
                child: Image.network(
                  item.imageUrl,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      style: const TextStyle(color: Colors.black54, fontSize: 12),
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
