// lib/widgets/tecla_numerica_button.dart
import 'dart:async';

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
  static const _duracionAzul = Duration(milliseconds: 100);

  bool _pressed = false;
  DateTime? _pressedAt;
  Timer? _releaseTimer;

  @override
  void dispose() {
    _releaseTimer?.cancel();
    super.dispose();
  }

  void _activarPressed() {
    _releaseTimer?.cancel();
    _pressedAt = DateTime.now();
    if (!_pressed) setState(() => _pressed = true);
  }

  void _programarSoltar() {
    _releaseTimer?.cancel();
    final inicio = _pressedAt;
    if (inicio == null) {
      if (_pressed && mounted) setState(() => _pressed = false);
      return;
    }
    final restante =
        _duracionAzul - DateTime.now().difference(inicio);
    if (restante <= Duration.zero) {
      if (mounted) setState(() => _pressed = false);
      return;
    }
    _releaseTimer = Timer(restante, () {
      _releaseTimer = null;
      if (mounted) setState(() => _pressed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final bg = enabled && _pressed ? AppTheme.colorPrimario : widget.color;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _activarPressed() : null,
      onTapUp: enabled ? (_) => _programarSoltar() : null,
      onTapCancel: enabled ? _programarSoltar : null,
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
