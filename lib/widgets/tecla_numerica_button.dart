// lib/widgets/tecla_numerica_button.dart
import 'package:flutter/material.dart';

import '../utils/theme.dart';

/// Tecla de teclado numérico: sin ripple Material; azul plano al pulsar.
class TeclaNumericaButton extends StatefulWidget {
  final Widget child;
  final Color color;
  final VoidCallback? onTap;
  final double borderRadius;

  const TeclaNumericaButton({
    super.key,
    required this.child,
    required this.color,
    this.onTap,
    this.borderRadius = 10,
  });

  @override
  State<TeclaNumericaButton> createState() => _TeclaNumericaButtonState();
}

class _TeclaNumericaButtonState extends State<TeclaNumericaButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final bg = enabled && _pressed ? AppTheme.colorPrimario : widget.color;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
        child: Center(child: widget.child),
      ),
    );
  }
}
