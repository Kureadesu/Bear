import 'package:material_ui/material_ui.dart';

import '../profile_helpers.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.radius = 26,
  });
  final String name;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF29456C),
      foregroundColor: const Color(0xFFDBE7FF),
      child: Text(
        initialsFor(name),
        style: TextStyle(fontSize: radius * .65, fontWeight: FontWeight.w700),
      ),
    );
    if (photoUrl == null || photoUrl!.isEmpty) return fallback;
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: ClipOval(
        child: Image.network(
          photoUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : fallback,
        ),
      ),
    );
  }
}
