class WardrobeItem {
  final String id;
  final String label;
  final String category;
  final String imagePath;
  final String dominantColorHex;
  final int createdAtMs;

  WardrobeItem({
    required this.id,
    required this.label,
    required this.category,
    required this.imagePath,
    required this.dominantColorHex,
    required this.createdAtMs,
  });

  Map<String, dynamic> toMap() => {
    "id": id,
    "label": label,
    "category": category,
    "imagePath": imagePath,
    "dominantColorHex": dominantColorHex,
    "createdAtMs": createdAtMs,
  };

  static WardrobeItem fromMap(Map map) => WardrobeItem(
    id: map["id"],
    label: map["label"],
    category: map["category"],
    imagePath: map["imagePath"],
    dominantColorHex: (map["dominantColorHex"] ?? "#999999"),
    createdAtMs: map["createdAtMs"],
  );
}
