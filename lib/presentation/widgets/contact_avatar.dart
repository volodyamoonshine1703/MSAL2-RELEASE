import '../../core/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

/// Lightweight avatar: shows colored initials.
/// For staff emails (@msal.ru but NOT @edu.msal.ru) — adds a green checkmark badge.
class ContactAvatar extends ConsumerWidget {
  final String name;
  final String email;
  final double size;

  const ContactAvatar({
    super.key,
    required this.name,
    required this.email,
    this.size = 40,
  });

  /// Staff = @msal.ru domain but NOT @edu.msal.ru (students)
  bool get _isStaff {
    final e = email.toLowerCase().trim();
    if (e.isEmpty) return false;
    return e.endsWith('@msal.ru') && !e.endsWith('@edu.msal.ru');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatar = _buildInitials();

    if (!_isStaff) return avatar;

    // Staff badge: green checkmark
    return SizedBox(
      width: size + 4,
      height: size + 4,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 0, top: 0, child: avatar),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.38,
              height: size * 0.38,
              decoration: BoxDecoration(
                color: const Color(0xFF2ECC71),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF121212),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2ECC71).withOpacity(0.4),
                    blurRadius: 4,
                    spreadRadius: 0,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: size * 0.22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitials() {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();

    String initials = '';
    if (parts.length >= 2) {
      initials = '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty) {
      initials = parts[0][0].toUpperCase();
    } else {
      initials = '?';
    }

    // Generate color from email for consistency
    final hash = email.toLowerCase().codeUnits.fold(0, (prev, curr) => prev + curr);
    final hue = (hash * 137.5) % 360;
    final color = HSLColor.fromAHSL(1, hue, 0.5, 0.4).toColor();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: color,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
