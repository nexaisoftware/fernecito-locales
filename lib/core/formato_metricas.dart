library;

/// Formato compacto para métricas en UI (KPIs, ejes de gráficos).
/// Tooltips y detalle pueden usar [formatoMetricaExacto].
String formatoMetricaCompacto(num value) {
  final n = value.abs().toDouble();
  final signo = value < 0 ? '-' : '';
  if (n < 1000) {
    return '$signo${n % 1 == 0 ? n.toInt().toString() : _sinDecimalCero(n.toStringAsFixed(1))}';
  }
  if (n < 1000000) {
    final k = n / 1000;
    final texto = k >= 100
        ? k.round().toString()
        : _sinDecimalCero(k.toStringAsFixed(k >= 10 ? 0 : 1));
    return '$signo${texto}K';
  }
  final m = n / 1000000;
  final texto = m >= 100
      ? m.round().toString()
      : _sinDecimalCero(m.toStringAsFixed(m >= 10 ? 0 : 1));
  return '$signo${texto}M';
}

/// Valor exacto legible (tooltips, accesibilidad).
String formatoMetricaExacto(num value) {
  final n = value.abs().toDouble();
  final signo = value < 0 ? '-' : '';
  if (n % 1 == 0) return '$signo${_separarMiles(n.toInt().toString())}';
  return '$signo${_separarMiles(_sinDecimalCero(n.toStringAsFixed(1)))}';
}

String _sinDecimalCero(String value) =>
    value.endsWith('.0') ? value.substring(0, value.length - 2) : value;

String _separarMiles(String value) {
  final partes = value.split('.');
  final entero = partes.first;
  final buffer = StringBuffer();
  for (var i = 0; i < entero.length; i++) {
    final desdeFinal = entero.length - i;
    buffer.write(entero[i]);
    if (desdeFinal > 1 && desdeFinal % 3 == 1) buffer.write('.');
  }
  if (partes.length > 1) buffer.write(',${partes[1]}');
  return buffer.toString();
}
