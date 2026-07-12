import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app.dart';

class AppMenuAction<T> {
  final T value;
  final IconData icon;
  final String label;
  final bool enabled;
  final bool selected;
  final bool destructive;

  const AppMenuAction({
    required this.value,
    required this.icon,
    required this.label,
    this.enabled = true,
    this.selected = false,
    this.destructive = false,
  });
}

/// A popup menu that never intentionally covers its trigger.
///
/// Menus open below the anchor with a small gap. Flutter's [MenuAnchor]
/// automatically flips the complete panel above bottom-aligned controls and
/// keeps it clear of view insets such as the software keyboard.
class AppAnchoredMenuButton<T> extends StatefulWidget {
  final String tooltip;
  final List<AppMenuAction<T>> actions;
  final ValueChanged<T> onSelected;
  final bool enabled;
  final Widget? icon;
  final Widget? child;
  final BorderRadius borderRadius;

  const AppAnchoredMenuButton({
    super.key,
    required this.tooltip,
    required this.actions,
    required this.onSelected,
    this.enabled = true,
    this.icon,
    this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  }) : assert(icon == null || child == null);

  @override
  State<AppAnchoredMenuButton<T>> createState() =>
      _AppAnchoredMenuButtonState<T>();
}

class _AppAnchoredMenuButtonState<T> extends State<AppAnchoredMenuButton<T>> {
  static const _gap = 6.0;
  final _controller = MenuController();
  final _anchorKey = GlobalKey();
  double _maximumMenuHeight = 400;

  @override
  void didUpdateWidget(covariant AppAnchoredMenuButton<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _controller.isOpen) _controller.close();
  }

  void _toggle() {
    if (!widget.enabled) return;
    if (_controller.isOpen) {
      _controller.close();
      return;
    }

    final anchor = _anchorKey.currentContext?.findRenderObject();
    final overlay = Overlay.of(
      context,
      rootOverlay: true,
    ).context.findRenderObject();
    if (anchor is RenderBox && overlay is RenderBox) {
      final media = MediaQuery.of(context);
      final origin = anchor.localToGlobal(Offset.zero, ancestor: overlay);
      final safeTop = media.padding.top + 8;
      final safeBottom =
          overlay.size.height -
          math.max(media.padding.bottom, media.viewInsets.bottom) -
          8;
      final above = math.max(48.0, origin.dy - safeTop - _gap);
      final below = math.max(
        48.0,
        safeBottom - origin.dy - anchor.size.height - _gap,
      );
      _maximumMenuHeight = math.max(above, below);
    }

    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.enabled) _controller.open();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final popupTheme = theme.popupMenuTheme;
    final popupShape = popupTheme.shape;
    return MenuAnchor(
      controller: _controller,
      useRootOverlay: true,
      consumeOutsideTap: true,
      reservedPadding: const EdgeInsets.all(8),
      alignmentOffset: const Offset(0, _gap),
      style: MenuStyle(
        alignment: AlignmentDirectional.bottomStart,
        backgroundColor: WidgetStatePropertyAll(
          popupTheme.color ?? AppColors.surface,
        ),
        surfaceTintColor: WidgetStatePropertyAll(
          popupTheme.surfaceTintColor ?? Colors.transparent,
        ),
        shadowColor: WidgetStatePropertyAll(
          popupTheme.shadowColor ?? AppColors.ink.withValues(alpha: .12),
        ),
        elevation: WidgetStatePropertyAll(popupTheme.elevation ?? 5),
        shape: WidgetStatePropertyAll(
          popupShape is OutlinedBorder
              ? popupShape
              : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: AppColors.line),
                ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(168, 0)),
        maximumSize: WidgetStatePropertyAll(Size(280, _maximumMenuHeight)),
      ),
      menuChildren: [
        for (final action in widget.actions) _item(context, action),
      ],
      builder: (context, controller, _) {
        if (widget.icon != null) {
          return KeyedSubtree(
            key: _anchorKey,
            child: IconButton(
              tooltip: widget.tooltip,
              onPressed: widget.enabled ? _toggle : null,
              icon: widget.icon!,
            ),
          );
        }
        return KeyedSubtree(
          key: _anchorKey,
          child: Tooltip(
            message: widget.tooltip,
            child: Semantics(
              button: true,
              enabled: widget.enabled,
              label: widget.tooltip,
              excludeSemantics: true,
              child: InkWell(
                onTap: widget.enabled ? _toggle : null,
                borderRadius: widget.borderRadius,
                child: widget.child ?? const SizedBox(width: 48, height: 48),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _item(BuildContext context, AppMenuAction<T> action) {
    final color = action.destructive
        ? AppColors.coral
        : action.selected
        ? AppColors.moss
        : null;
    return MenuItemButton(
      semanticsLabel: action.label,
      onPressed: action.enabled ? () => widget.onSelected(action.value) : null,
      leadingIcon: Icon(action.icon, size: 19, color: color),
      trailingIcon: action.selected
          ? const Icon(Icons.check_rounded, size: 18, color: AppColors.moss)
          : null,
      style: MenuItemButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(168, 48),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      child: Text(action.label),
    );
  }
}
