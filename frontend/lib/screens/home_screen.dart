import 'dart:ui';
import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  String selectedPrompt = '';

  // Example prompts
  final List<String> prompts = ['Date', 'College', 'Party', 'Formal Meeting'];

  // Sample products (replace with your actual data)
  final List<ProductItem> products = [
    ProductItem(
      name: 'Classic Tuxedo',
      category: 'Formal',
      price: '\$299',
      imageUrl: 'https://via.placeholder.com/200',
      rating: 4.8,
    ),
    ProductItem(
      name: 'Summer Dress',
      category: 'Casual',
      price: '\$89',
      imageUrl: 'https://via.placeholder.com/200',
      rating: 4.5,
    ),
    ProductItem(
      name: 'Business Suit',
      category: 'Formal',
      price: '\$399',
      imageUrl: 'https://via.placeholder.com/200',
      rating: 4.9,
    ),
    ProductItem(
      name: 'Party Outfit',
      category: 'Party',
      price: '\$149',
      imageUrl: 'https://via.placeholder.com/200',
      rating: 4.6,
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
              Color(0xFFFFF8E1), // Warm cream on top
              Colors.white,      // Fades to pure white on the bottom
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.4],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),

                // Greeting text
                _buildGreeting(),

                const SizedBox(height: 25),

                // Example prompts
                _buildPromptChips(),

                const SizedBox(height: 15),

                // AI Search bar with glassmorphism
                _buildSearchBar(),

                const SizedBox(height: 30),

                // Divider
                _buildDivider(),

                const SizedBox(height: 30),

                // Products section header
                const Text(
                  'Recommended for You',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),

                const SizedBox(height: 20),

                // Vertically scrollable product boxes
                _buildProductList(),

                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGreeting() {
    return const Text(
      "Hey!\nWhat's the occasion\nfor today?",
      style: TextStyle(
        fontFamily: 'serif',
        fontSize: 30,
        height: 1.1,
        fontWeight: FontWeight.w500,
        color: Colors.black87,
        letterSpacing: -0.5,
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

  Widget _buildPromptChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: prompts.map((prompt) {
        final isSelected = selectedPrompt == prompt;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: GestureDetector(
            onTap: () {
              setState(() {
                selectedPrompt = prompt;
                _searchController.text = prompt;
              });
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: isSelected
                    ? LinearGradient(
                  colors: [
                    Colors.grey.shade700.withOpacity(0.3),
                    Colors.grey.shade500.withOpacity(0.2),
                  ],
                )
                    : LinearGradient(
                  colors: [
                    Colors.grey.shade400.withOpacity(0.15),
                    Colors.grey.shade300.withOpacity(0.1),
                  ],
                ),
                border: Border.all(
                  color: isSelected
                      ? Colors.white.withOpacity(0.6)
                      : Colors.white.withOpacity(0.4),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    spreadRadius: -2,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                prompt,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
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
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.black.withOpacity(0.05),
              border: Border.all(
                color: Colors.black.withOpacity(0.2),
                width: 1.5,
              ),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: 'Describe your style or occasion...',
                hintStyle: TextStyle(
                  color: Colors.black54.withOpacity(0.6),
                  fontSize: 15,
                ),
                prefixIcon: const Icon(
                  Icons.auto_awesome,
                  color: Colors.black87,
                  size: 24,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: Icon(
                    Icons.send,
                    color: Colors.black54.withOpacity(0.7),
                    size: 22,
                  ),
                  onPressed: () {
                    // Handle AI search
                    print('Searching for: ${_searchController.text}');
                  },
                )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
              ),
              onChanged: (value) {
                setState(() {});
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: products.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 15),
          child: _buildProductCard(products[index]),
        );
      },
    );
  }

  Widget _buildProductCard(ProductItem product) {
    return Container(
      width: double.infinity,
      height: 140,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
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
        borderRadius: BorderRadius.circular(25),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
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
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Product image/icon
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.checkroom,
                        size: 45,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),

                  const SizedBox(width: 16),

                  // Product details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          product.category,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black54.withOpacity(0.7),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              product.price,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            Row(
                              children: [
                                Icon(
                                  Icons.star,
                                  size: 18,
                                  color: Colors.amber.shade700,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  product.rating.toString(),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
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
  }
}

// Product model
class ProductItem {
  final String name;
  final String category;
  final String price;
  final String imageUrl;
  final double rating;

  ProductItem({
    required this.name,
    required this.category,
    required this.price,
    required this.imageUrl,
    required this.rating,
  });
}