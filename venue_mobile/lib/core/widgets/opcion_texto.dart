import 'package:flutter/material.dart';

/// Selección por texto y subrayado. Sin chips, cápsulas ni fondos de estado.
class OpcionTexto extends StatelessWidget {
  const OpcionTexto({
    super.key,
    required this.label,
    this.selected = false,
    this.onSelected,
    this.onPressed,
    this.showCheckmark = false,
    this.visualDensity,
    this.side,
  });
  final Widget label;
  final bool selected, showCheckmark;
  final ValueChanged<bool>? onSelected;
  final VoidCallback? onPressed;
  final VisualDensity? visualDensity;
  final BorderSide? side;
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    final contenido = Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        border: selected ? Border(bottom: BorderSide(color: color)) : null,
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: color,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
        ),
        child: label,
      ),
    );
    if (onSelected == null && onPressed == null) return contenido;
    return Semantics(
      selected: selected,
      button: true,
      child: TextButton(
        onPressed: onPressed ?? () => onSelected!(!selected),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: const RoundedRectangleBorder(),
        ),
        child: contenido,
      ),
    );
  }
}
