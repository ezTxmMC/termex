import 'package:flutter/material.dart';

class TerminalTitleBar extends StatelessWidget {
  const TerminalTitleBar({
    super.key,
    this.title = 'Termex',
    this.onClose,
    this.onMinimize,
    this.onMaximize,
    this.height = 38.0,
  });

  final String title;
  final VoidCallback? onClose;
  final VoidCallback? onMinimize;
  final VoidCallback? onMaximize;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        border: Border(bottom: BorderSide(color: Color(0xFF30363D))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          _TrafficDot(color: const Color(0xFFFF5F57), onTap: onClose ?? () {}),
          const SizedBox(width: 8),
          _TrafficDot(
            color: const Color(0xFFFFBD2E),
            onTap: onMinimize ?? () {},
          ),
          const SizedBox(width: 8),
          _TrafficDot(
            color: const Color(0xFF28C840),
            onTap: onMaximize ?? () {},
          ),
          Expanded(
            child: Center(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 12,
                  color: Color(0xFF8B949E),
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          const SizedBox(width: 68),
        ],
      ),
    );
  }
}

class _TrafficDot extends StatelessWidget {
  const _TrafficDot({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
