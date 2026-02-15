enum WardrobeCategory { outerwear, top, bottom, shoes, accessory }

WardrobeCategory parseWardrobeCategory(String raw) {
  final v = raw.trim().toLowerCase();
  switch (v) {
    case 'outerwear':
      return WardrobeCategory.outerwear;
    case 'top':
      return WardrobeCategory.top;
    case 'bottom':
      return WardrobeCategory.bottom;
    case 'shoes':
      return WardrobeCategory.shoes;
    case 'accessory':
      return WardrobeCategory.accessory;
    default:
    // Fail “safe” to keep UI stable if backend ever slips.
      return WardrobeCategory.top;
  }
}

String wardrobeCategoryToApi(WardrobeCategory c) => c.name; // enum name is singular
