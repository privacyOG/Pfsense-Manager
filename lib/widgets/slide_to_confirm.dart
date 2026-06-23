import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SlideToConfirm extends StatefulWidget {
  const SlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.icon = Icons.warning_amber_rounded,
    this.color,
  });

  final String label;
  final VoidCallback onConfirmed;
  final IconData icon;
  final Color? color;

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0;
  bool _confirmed = false;
  static const double _thumbSize = 56;
  static const double _trackHeight = 60;

  late AnimationController _snapController;
  late Animation<double> _snapAnimation;
  double _snapFrom = 0;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _snapController.addListener(() {
      setState(() => _dragOffset = _snapAnimation.value);
    });
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details, double trackWidth) {
    if (_confirmed) return;
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dx).clamp(
        0,
        trackWidth - _thumbSize,
      );
    });
  }

  void _onDragEnd(DragEndDetails details, double trackWidth) {
    if (_confirmed) return;
    final threshold = trackWidth - _thumbSize;
    if (_dragOffset >= threshold * 0.88) {
      setState(() {
        _dragOffset = threshold;
        _confirmed = true;
      });
      HapticFeedback.heavyImpact();
      widget.onConfirmed();
    } else {
      _snapFrom = _dragOffset;
      _snapAnimation = Tween<double>(begin: _snapFrom, end: 0).animate(
        CurvedAnimation(parent: _snapController, curve: Curves.elasticOut),
      );
      _snapController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dangerColor = widget.color ?? scheme.error;

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final progress = trackWidth > _thumbSize
            ? (_dragOffset / (trackWidth - _thumbSize)).clamp(0.0, 1.0)
            : 0.0;

        return SizedBox(
          height: _trackHeight,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: _trackHeight,
                decoration: BoxDecoration(
                  color: Color.lerp(
                    dangerColor.withValues(alpha: 0.12),
                    dangerColor.withValues(alpha: 0.28),
                    progress,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: dangerColor.withValues(alpha: 0.38),
                  ),
                ),
              ),
              if (!_confirmed)
                Padding(
                  padding: const EdgeInsets.only(left: _thumbSize + 12),
                  child: Center(
                    child: Opacity(
                      opacity: (1.0 - progress * 2).clamp(0.0, 1.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chevron_right, color: dangerColor, size: 18),
                          Icon(Icons.chevron_right,
                              color: dangerColor.withValues(alpha: 0.5), size: 18),
                          const SizedBox(width: 6),
                          Text(
                            widget.label,
                            style: TextStyle(
                              color: dangerColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: _dragOffset,
                child: GestureDetector(
                  onHorizontalDragUpdate: (d) =>
                      _onDragUpdate(d, trackWidth),
                  onHorizontalDragEnd: (d) =>
                      _onDragEnd(d, trackWidth),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: BoxDecoration(
                      color: _confirmed
                          ? dangerColor.withValues(alpha: 0.2)
                          : dangerColor,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: dangerColor.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      _confirmed ? Icons.check : widget.icon,
                      color: _confirmed ? dangerColor : scheme.onError,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<bool?> showSlideToConfirmSheet({
  required BuildContext context,
  required String title,
  required String body,
  required String slideLabel,
  IconData icon = Icons.warning_amber_rounded,
  Color? color,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isDismissible: true,
    enableDrag: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      final dangerColor = color ?? scheme.error;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(icon, color: dangerColor, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                body,
                style: Theme.of(ctx)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              SlideToConfirm(
                label: slideLabel,
                icon: icon,
                color: dangerColor,
                onConfirmed: () => Navigator.pop(ctx, true),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
