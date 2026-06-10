library;

/// Formato compacto para métricas en UI (KPIs, ejes de gráficos).
/// Tooltips y detalle pueden usar [formatoMetricaExacto].
String formatoMetricaCompacto(num value) {
  final n = value.toDouble();
  if (n < 1000) return n % 1 == 0 ? n.toInt().toString() : n.toStringAsFixed(1);
  if (n < 1000000) {
    final k = n / 1000;
    return k >= 100 ? '${k.round()}k' : '${k.toStringAsFixed(k >= 10 ? 0 : 1)}k';
  }
  final m = n / 1000000;
  return m >= 100 ? '${m.round()}M' : '${m.toStringAsFixed(m >= 10 ? 0 : 1)}M';
}

/// Valor exacto legible (tooltips, accesibilidad).
String formatoMetricaExacto(num value) {
  final n = value.toDouble();
  if (n % 1 == 0) return n.toInt().toString();
  return n.toStringAsFixed(1);
}
