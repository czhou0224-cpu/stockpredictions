import 'package:flutter/material.dart';

class PlaceholderPage extends StatelessWidget {
  final String title;
  final IconData icon;

  const PlaceholderPage({
    super.key,
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.white70),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}