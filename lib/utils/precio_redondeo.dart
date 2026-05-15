// Redondeo monetario alineado con el cálculo de totales en pedidos.php (PVP a 2 decimales).

double redondearMoneda(double euros) => (euros * 100).round() / 100.0;

/// Base sin IVA unitaria + suplementos sin IVA de opciones no predeterminadas.
double baseImponibleUnitariaProductoLinea({
  required double baseImponibleProducto,
  required Iterable<double> suplementosSinIvaNoPredeterminados,
}) {
  var b = baseImponibleProducto;
  for (final s in suplementosSinIvaNoPredeterminados) {
    b += s;
  }
  return b;
}

/// PVP unitario (IVA incluido) redondeado a céntimos.
double pvpUnitarioDesdeBaseSinIva({
  required double baseSinIvaUnitaria,
  required double porcentajeIva,
}) {
  final factor = 1 + porcentajeIva / 100;
  return redondearMoneda(baseSinIvaUnitaria * factor);
}

/// Importe total TTC de la línea (cantidad × PVP unitario redondeado).
double importeTtcLinea({
  required double pvpUnitario,
  required int cantidad,
}) {
  return redondearMoneda(pvpUnitario * cantidad);
}

/// Descompone el TTC de una línea en base e IVA (2 decimales, suma = TTC).
({double base, double iva}) baseEIvaDesdeTtcLinea({
  required double importeTtc,
  required double porcentajeIva,
}) {
  final factor = 1 + porcentajeIva / 100;
  final base = redondearMoneda(importeTtc / factor);
  final iva = redondearMoneda(importeTtc - base);
  return (base: base, iva: iva);
}
