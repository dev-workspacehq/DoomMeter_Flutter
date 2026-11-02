import 'package:flutter/material.dart';

import '../../domain/params/increment_social_count_params.dart';

class SocialCounter extends StatelessWidget {
  const SocialCounter({
    required this.platform,
    required this.count,
    required this.enabled,
    this.lastActivityAt,
    this.onTap,
    super.key,
  });

  final SocialPlatform platform;
  final int count;
  final DateTime? lastActivityAt;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = switch (platform) {
      SocialPlatform.instagram => 'Instagram',
      SocialPlatform.youtube => 'YouTube',
    };
    final timestamp = lastActivityAt;
    final activityLabel = timestamp == null
        ? 'No activity'
        : 'Last activity: ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(timestamp.toLocal()), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
    final interactive = enabled && onTap != null;
    return Semantics(
      label:
          '$label: $count. $activityLabel${interactive ? '' : '. Read only'}',
      button: true,
      enabled: interactive,
      onTap: interactive ? onTap : null,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('${platform.name}-counter'),
        onTap: interactive ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$count',
                  key: ValueKey('${platform.name}-count'),
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 64,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox.square(
                dimension: 36,
                child: RepaintBoundary(
                  child: CustomPaint(painter: _SocialIconPainter(platform)),
                ),
              ),
              const SizedBox(height: 10),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                activityLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small vector marks keep the two platform icons sharp without an icon package.
class _SocialIconPainter extends CustomPainter {
  const _SocialIconPainter(this.platform);

  final SocialPlatform platform;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 36, size.height / 36);
    if (platform == SocialPlatform.instagram) {
      final paint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [Color(0xFFF9A341), Color(0xFFE23978), Color(0xFF843DC5)],
        ).createShader(const Rect.fromLTWH(0, 0, 36, 36))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(3, 3, 30, 30),
          const Radius.circular(9),
        ),
        paint,
      );
      canvas.drawCircle(const Offset(18, 18), 7, paint);
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(const Offset(26, 10), 2, paint);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 6, 36, 24),
          const Radius.circular(7),
        ),
        Paint()..color = const Color(0xFFFF0033),
      );
      canvas.drawPath(
        Path()
          ..moveTo(15, 12)
          ..lineTo(15, 24)
          ..lineTo(25, 18)
          ..close(),
        Paint()..color = Colors.white,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SocialIconPainter oldDelegate) =>
      oldDelegate.platform != platform;
}
