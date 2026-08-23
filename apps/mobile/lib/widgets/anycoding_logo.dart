import 'package:flutter/material.dart';

/// AnyCoding iconic brand symbol.
///
/// Combines the structural letter "A" with a command-line prompt chevron ">"
/// and execution pulse, highlighting the dual Codex (cyan) & Antigravity (orange) engines.
class AnyCodingLogo extends StatelessWidget {
  final double size;
  final bool showContainer;
  final BorderRadius? borderRadius;

  const AnyCodingLogo({
    super.key,
    this.size = 28,
    this.showContainer = false,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final logoWidget = CustomPaint(
      size: Size(size, size),
      painter: _AnyCodingLogoPainter(),
    );

    if (!showContainer) return logoWidget;

    return Container(
      width: size * 1.35,
      height: size * 1.35,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF0B0F19),
        borderRadius: borderRadius ?? BorderRadius.circular(size * 0.35),
        border: Border.all(
          color: const Color(0xFF24324D),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: logoWidget,
    );
  }
}

class _AnyCodingLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final scale = w / 100.0;

    // Paints
    final leftLegPaint = Paint()
      ..color = const Color(0xFFFF7A00) // Antigravity Warm Orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final promptChevronPaint = Paint()
      ..color = const Color(0xFF00D2B4) // Codex Cyan / Teal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final dotPaint = Paint()
      ..color = const Color(0xFF38BDF8) // Sky highlight
      ..style = PaintingStyle.fill;

    // Left diagonal stroke of 'A' (from bottom-left to top apex)
    final leftPath = Path()
      ..moveTo(22 * scale, 82 * scale)
      ..lineTo(50 * scale, 18 * scale);
    canvas.drawPath(leftPath, leftLegPaint);

    // Command Prompt Chevron '>' forming crossbar and right descender
    final promptPath = Path()
      ..moveTo(38 * scale, 48 * scale)
      ..lineTo(76 * scale, 58 * scale)
      ..lineTo(48 * scale, 82 * scale);
    canvas.drawPath(promptPath, promptChevronPaint);

    // Subtle terminal pulse dot at the apex
    canvas.drawCircle(
      Offset(50 * scale, 18 * scale),
      5.5 * scale,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
