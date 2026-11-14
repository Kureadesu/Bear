import 'package:characters/characters.dart';

String initialsFor(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  final first = words.first.characters.first;
  final last = words.length > 1 ? words.last.characters.first : '';
  return '$first$last'.toUpperCase();
}

// Legacy users already chose a name; don't reset their pairing or onboarding.
bool needsProfileSetup(Map<String, dynamic> profile) {
  if (profile['profileComplete'] == false) return true;
  final name = profile['displayName'];
  return name is! String || name.trim().isEmpty;
}

String? validateDisplayName(String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) return 'Please choose a display name.';
  if (name.length > 80) return 'Use 80 characters or fewer.';
  return null;
}

String? validatePhotoUrl(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (text.length > 2000 ||
      uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty) {
    return 'Use a complete HTTPS image URL, or leave this empty.';
  }
  return null;
}
