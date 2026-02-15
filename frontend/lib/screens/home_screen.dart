import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController();

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
      String current = _phrases[_phraseIndex];

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Set to white to match the bottom of your gradient
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFFFF8E1), // The warm "cream" color
              Colors.white,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.45], // Transition finishes early for a soft look
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

              // Quick Options Horizontal Scroll
              SliverToBoxAdapter(
                child: _buildQuickOptions(),
              ),

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
                    childCount: 10,
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 20)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickOptions() {
    final List<String> options = ["College", "Date", "Party", "Formal"];
    return SizedBox(
      height: 42, // Increased slightly for better tap target
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // Adding internal padding here allows buttons to scroll "into" the screen edges
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          return InkWell(
            onTap: () => _controller.text = "I need an outfit for ${options[i].toLowerCase()}",
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
            // FIX: Vertical padding was making it uneven.
            // Better to control height via contentPadding inside the TextField.
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _controller,
              textAlignVertical: TextAlignVertical.center, // Centers text vertically
              decoration: InputDecoration(
                border: InputBorder.none,
                // Using contentPadding ensures the icon and text line up perfectly
                contentPadding: const EdgeInsets.symmetric(vertical: 18),
                hintText: "$_hintText${_showCursor ? '|' : ' '}",
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 16),
                prefixIcon: const Icon(Icons.auto_awesome, color: Colors.blueAccent),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded, color: Colors.black),
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ... rest of your build methods (_buildSeparator, _buildPinterestCard, _cardButton)
  // remain the same as your original code.

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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        image: DecorationImage(
          image: NetworkImage("https://picsum.photos/id/${index + 10}/400/600"),
          fit: BoxFit.cover,
        ),
      ),
      child: Stack(
        children: [
          // Gradient Overlay for buttons visibility
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.4)],
                  stops: const [0.6, 1.0],
                ),
              ),
            ),
          ),
          // Like/Dislike Buttons
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _cardButton(Icons.close, Colors.white24),
                _cardButton(Icons.favorite_rounded, Colors.white),
              ],
            ),
          ),
        ],
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