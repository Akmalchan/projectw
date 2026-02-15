import 'dart:io';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'wardrobe_item.dart';

class WardrobeStore {
  static const _boxName = "wardrobe_items";
  static const _metaBoxName = "wardrobe_meta";
  static final _uuid = const Uuid();


  static const _seedKey = "seed_version";
  static const int seedVersion = 4;


  static Future<void> init() async {
    await Hive.openBox(_boxName);
    await Hive.openBox(_metaBoxName);
  }

  static Box get _box => Hive.box(_boxName);
  static Box get _meta => Hive.box(_metaBoxName);

  static Future<Directory> _wardrobeDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final w = Directory("${dir.path}/wardrobe");
    if (!await w.exists()) await w.create(recursive: true);
    return w;
  }

  static Future<String> _copyAssetToLocal(String assetPath, String fileName) async {
    final bytes = await rootBundle.load(assetPath);
    final dir = await _wardrobeDir();
    final file = File("${dir.path}/$fileName");
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return file.path;
  }

  // TEST: Seed fake items once (only if DB empty)
  static Future<void> seedIfEmpty() async {
    if (_box.isNotEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    final samples = [
      ("assets/wardrobe/fake1.jpg", "Ferrari jacket", "outerwear", "#D32F2F"),
      ("assets/wardrobe/fake2.jpg", "Black coat", "outerwear", "#1E1E1E"),
      ("assets/wardrobe/fake3.jpg", "Pajama set", "pants", "#5C6BC0"),
      ("assets/wardrobe/fake4.jpg", "Dildo", "outerwear", "#1E1E1E"),
      ("assets/wardrobe/fake5.jpg", "But Plug", "pants", "#5C6BC0"),


      ("assets/wardrobe/coat1.jpg", "Black Overcoat", "outerwear", "#D32F2F"),
      ("assets/wardrobe/coat2.jpg", "Khaki coat", "outerwear", "#1E1E1E"),
      ("assets/wardrobe/jacket1.jpg", "Ferrari jacket", "outerwear", "#5C6BC0"),
      ("assets/wardrobe/jacket2.jpg", "Leather Jacket", "outerwear", "#1E1E1E"),
      ("assets/wardrobe/jacket3.jpg", "Utility Jacket", "outerwear", "#5C6BC0"),
      ("assets/wardrobe/jacket4.jpg", "Polo Jacket", "outerwear", "#5C6BC0"),

      ("assets/wardrobe/polo1.jpg", "Blue Polo", "outerwear", "#D32F2F"),
      ("assets/wardrobe/polo2.jpg", "Black Polo", "outerwear", "#1E1E1E"),
      ("assets/wardrobe/shirt1.jpg", "Blue Shirt", "outerwear", "#5C6BC0"),
      ("assets/wardrobe/sweater1.jpg", "Grey Sweater", "outerwear", "#1E1E1E"),
      ("assets/wardrobe/sweater2.jpg", "Green Sweater", "outerwear", "#5C6BC0"),

      ("assets/wardrobe/pants1.jpg", "Golf Pants", "outerwear", "#D32F2F"),
      ("assets/wardrobe/pants2.jpg", "Dark Jeans", "outerwear", "#1E1E1E"),
      ("assets/wardrobe/pants3.jpg", "Light Jeans", "outerwear", "#5C6BC0"),
      ("assets/wardrobe/pants4.jpg", "Dark Trousers", "outerwear", "#1E1E1E"),

      ("assets/wardrobe/sneakers1.jpg", "Polo Sneaker", "outerwear", "#D32F2F"),
      ("assets/wardrobe/boots1.jpg", "Dark Boots", "outerwear", "#1E1E1E"),
      ("assets/wardrobe/boots2.jpg", "Oslo Boots", "outerwear", "#5C6BC0"),
    ];


    for (final s in samples) {
      final id = _uuid.v4();
      final localPath = await _copyAssetToLocal(s.$1, "$id.jpg");

      final item = WardrobeItem(
        id: id,
        label: s.$2,
        category: s.$3,
        imagePath: localPath,
        dominantColorHex: s.$4,
        createdAtMs: now,
      );

      await _box.put(id, item.toMap());
    }
  }

  static Future<void> seedIfNeeded() async {
    final last = (_meta.get(_seedKey, defaultValue: 0) as int);

    if (last >= seedVersion) return;

    // DEV BEHAVIOR (recommended): reset samples to match your new list
    await _box.clear();

    await seedIfEmpty(); // will now insert because box was cleared
    await _meta.put(_seedKey, seedVersion);
  }


  static Future<List<WardrobeItem>> getAll() async {
    final list = _box.values
        .map((e) => WardrobeItem.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    list.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return list;
  }

  static Future<List<WardrobeItem>> getByCategory(String category) async {
    final all = await getAll();
    if (category == "all") return all;
    return all.where((x) => x.category == category).toList();
  }

  // Later: for Gemini ingestion
  static Future<void> addItemFromBytes({
    required List<int> imageBytes,
    required String label,
    required String category,
    required String dominantColorHex,
  }) async {
    final id = _uuid.v4();
    final dir = await _wardrobeDir();
    final file = File("${dir.path}/$id.jpg");
    await file.writeAsBytes(imageBytes, flush: true);

    final item = WardrobeItem(
      id: id,
      label: label,
      category: category,
      imagePath: file.path,
      dominantColorHex: dominantColorHex,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    await _box.put(id, item.toMap());
  }

  static Future<void> deleteItem(WardrobeItem item) async {
    // 1) Delete from Hive (assuming you store by item.id as the key)
    await _box.delete(item.id);

    // 2) Delete the image file too (optional but recommended)
    try {
      final f = File(item.imagePath);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {
      // ignore file delete errors
    }
  }

}
