import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';

class SlideToConfirm extends StatefulWidget {
  const SlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.icon = Icons.warning_amber_rounded,
    this.color,
    this.semanticLabel,
    this.semanticHint,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onConfirmed;
  final IconData icon;
  final Color? color;
  final String? semanticLabel;
  final String? semanticHint;
  final bool autofocus;

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm>
    with SingleTickerProviderStateMixin {
  static const double _baseThumbSize = 56;
  static const double _minimumTrackHeight = 60;
  static const double _maximumTrackHeight = 108;

  double _dragOffset = 0;
  bool _confirmed = false;
  bool _hasFocus = false;

  late final AnimationController _snapController;
  late final FocusNode _focusNode;
  late Animation<double> _snapAnimation;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'SlideToConfirm');
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
    _focusNode.dispose();
    super.dispose();
  }

  void _onDragUpdate(
    DragUpdateDetails details,
    double maxDrag,
    bool isRtl,
  ) {
    if (_confirmed || maxDrag <= 0) return;
    final logicalDelta = details.delta.dx * (isRtl ? -1 : 1);
    setState(() {
      _dragOffset = (_dragOffset + logicalDelta).clamp(0, maxDrag);
    });
  }

  void _onDragEnd(DragEndDetails details, double maxDrag) {
    if (_confirmed || maxDrag <= 0) return;
    if (_dragOffset >= maxDrag * 0.88) {
      _confirm(maxDrag);
      return;
    }

    _snapAnimation = Tween<double>(begin: _dragOffset, end: 0).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.elasticOut),
    );
    _snapController.forward(from: 0);
  }

  void _confirm(double maxDrag) {
    if (_confirmed) return;
    _snapController.stop();
    setState(() {
      _dragOffset = maxDrag;
      _confirmed = true;
    });
    HapticFeedback.heavyImpact();
    widget.onConfirmed();
  }

  KeyEventResult _handleKeyEvent(KeyEvent event, double maxDrag) {
    if (_confirmed || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      _confirm(maxDrag);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dangerColor = widget.color ?? scheme.error;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final trackHeight = (_minimumTrackHeight +
            math.max(0, textScale - 1) * 28)
        .clamp(_minimumTrackHeight, _maximumTrackHeight)
        .toDouble();
    final thumbSize = math.min(
      _baseThumbSize + math.max(0, textScale - 1) * 4,
      trackHeight - 4,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final maxDrag = math.max(0.0, trackWidth - thumbSize);
        final progress = maxDrag > 0
            ? (_dragOffset / maxDrag).clamp(0.0, 1.0)
            : 0.0;
        final chevron =
            isRtl ? Icons.chevron_left : Icons.chevron_right;

        return Focus(
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          onKeyEvent: (_, event) => _handleKeyEvent(event, maxDrag),
          onFocusChange: (focused) {
            if (_hasFocus == focused) return;
            setState(() => _hasFocus = focused);
          },
          child: Semantics(
            key: const Key('slide-to-confirm'),
            container: true,
            button: true,
            enabled: !_confirmed,
            label: widget.semanticLabel ?? widget.label,
            hint: widget.semanticHint,
            value: '${(progress * 100).round()}%',
            onTap: _confirmed ? null : () => _confirm(maxDrag),
            excludeSemantics: true,
            child: SizedBox(
              height: trackHeight,
              child: MouseRegion(
                cursor: _confirmed
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.click,
                child: Stack(
                  alignment: AlignmentDirectional.centerStart,
                  children: [
                    Container(
                      height: trackHeight,
                      decoration: BoxDecoration(
                        color: Color.lerp(
                          dangerColor.withValues(alpha: 0.12),
                          dangerColor.withValues(alpha: 0.28),
                          progress,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _hasFocus
                              ? scheme.onSurface
                              : dangerColor.withValues(alpha: 0.38),
                          width: _hasFocus ? 2 : 1,
                        ),
                      ),
                    ),
                    if (!_confirmed)
                      Padding(
                        padding: EdgeInsetsDirectional.only(
                          start: thumbSize + 12,
                          end: 12,
                        ),
                        child: Center(
                          child: Opacity(
                            opacity: (1.0 - progress * 2).clamp(0.0, 1.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  chevron,
                                  color: dangerColor,
                                  size: 18,
                                ),
                                Icon(
                                  chevron,
                                  color: dangerColor.withValues(alpha: 0.5),
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    widget.label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: dangerColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    PositionedDirectional(
                      start: _dragOffset,
                      child: GestureDetector(
                        key: const Key('slide-to-confirm-thumb'),
                        behavior: HitTestBehavior.opaque,
                        onTap: _focusNode.requestFocus,
                        onHorizontalDragStart: (_) =>
                            _focusNode.requestFocus(),
                        onHorizontalDragUpdate: (details) =>
                            _onDragUpdate(details, maxDrag, isRtl),
                        onHorizontalDragEnd: (details) =>
                            _onDragEnd(details, maxDrag),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 80),
                          width: thumbSize,
                          height: thumbSize,
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
              ),
            ),
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
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      final dangerColor = color ?? scheme.error;
      final strings = Localizations.of<AppStrings>(ctx, AppStrings);
      final viewInsets = MediaQuery.viewInsetsOf(ctx);

      return SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            28 + viewInsets.bottom,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, color: dangerColor, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style:
                              Theme.of(ctx).textTheme.titleLarge?.copyWith(
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
                    semanticLabel: slideLabel,
                    icon: icon,
                    color: dangerColor,
                    onConfirmed: () => Navigator.pop(ctx, true),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(strings?.t('cancel') ?? 'Cancel'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
