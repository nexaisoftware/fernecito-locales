import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/models/actividad_metrica.dart';

void main() {
  group('inferirCategoriaActividadMetrica — eventos', () {
    test('evento Finalizado → eventoFinalizado', () {
      expect(
        inferirCategoriaActividadMetrica(
          tipo: TipoActividadMetrica.evento,
          estadoLabel: 'Finalizado',
        ),
        CategoriaActividadMetrica.eventoFinalizado,
      );
    });

    test('evento Cancelado → eventoCancelado', () {
      expect(
        inferirCategoriaActividadMetrica(
          tipo: TipoActividadMetrica.evento,
          estadoLabel: 'Cancelado',
        ),
        CategoriaActividadMetrica.eventoCancelado,
      );
    });

    test('evento con cualquier otro estado → eventoPublicado', () {
      for (final label in ['Publicado', 'Activo', 'Pendiente', '']) {
        expect(
          inferirCategoriaActividadMetrica(tipo: TipoActividadMetrica.evento, estadoLabel: label),
          CategoriaActividadMetrica.eventoPublicado,
          reason: 'estadoLabel "$label" debería → eventoPublicado',
        );
      }
    });
  });

  group('inferirCategoriaActividadMetrica — asistencias', () {
    test('asistencia "Invitación QR" → invitacionQr', () {
      expect(
        inferirCategoriaActividadMetrica(
          tipo: TipoActividadMetrica.asistencia,
          estadoLabel: 'Invitación QR',
        ),
        CategoriaActividadMetrica.invitacionQr,
      );
    });

    test('asistencia "Canjeada" → qrPase', () {
      expect(
        inferirCategoriaActividadMetrica(
          tipo: TipoActividadMetrica.asistencia,
          estadoLabel: 'Canjeada',
        ),
        CategoriaActividadMetrica.qrPase,
      );
    });

    test('asistencia "Rechazada" → listaRechazada', () {
      expect(
        inferirCategoriaActividadMetrica(
          tipo: TipoActividadMetrica.asistencia,
          estadoLabel: 'Rechazada',
        ),
        CategoriaActividadMetrica.listaRechazada,
      );
    });

    test('asistencia "Expirada" → listaRechazada', () {
      expect(
        inferirCategoriaActividadMetrica(
          tipo: TipoActividadMetrica.asistencia,
          estadoLabel: 'Expirada',
        ),
        CategoriaActividadMetrica.listaRechazada,
      );
    });

    test('asistencia con cualquier otro estado → listaAceptada', () {
      for (final label in ['Aceptada', 'Pendiente', '', 'Otro']) {
        expect(
          inferirCategoriaActividadMetrica(tipo: TipoActividadMetrica.asistencia, estadoLabel: label),
          CategoriaActividadMetrica.listaAceptada,
          reason: 'estadoLabel "$label" debería → listaAceptada',
        );
      }
    });
  });

  group('inferirCategoriaActividadMetrica — promos', () {
    test('promo siempre → qrPromo (independiente del estadoLabel)', () {
      for (final label in ['Canjeada', 'Activa', 'Expirada', '']) {
        expect(
          inferirCategoriaActividadMetrica(tipo: TipoActividadMetrica.promo, estadoLabel: label),
          CategoriaActividadMetrica.qrPromo,
          reason: 'promo con estadoLabel "$label" debería → qrPromo',
        );
      }
    });
  });

  group('CategoriaActividadMetricaLabels.etiquetaChip', () {
    test('cada categoría tiene etiqueta no vacía', () {
      for (final cat in CategoriaActividadMetrica.values) {
        expect(cat.etiquetaChip, isNotEmpty, reason: '${cat.name} sin etiqueta');
      }
    });

    test('etiquetas son únicas', () {
      final etiquetas = CategoriaActividadMetrica.values.map((c) => c.etiquetaChip).toSet();
      expect(etiquetas.length, CategoriaActividadMetrica.values.length);
    });
  });

  group('ActividadMetricaItem.lineaActor', () {
    ActividadMetricaItem _item({String? etiquetaActor, String? nombreActor}) =>
        ActividadMetricaItem(
          id: 'act-1',
          tipo: TipoActividadMetrica.asistencia,
          fecha: DateTime(2026, 6, 1),
          titulo: 'Test',
          subtitulo: 'Sub',
          estadoLabel: 'Aceptada',
          icono: Icons.check,
          colorEstado: Colors.green,
          etiquetaActor: etiquetaActor,
          nombreActor: nombreActor,
        );

    test('usa etiquetaActor si está disponible', () {
      final item = _item(etiquetaActor: 'Autoaceptada por mi local');
      expect(item.lineaActor, 'Autoaceptada por mi local');
    });

    test('usa "Por nombreActor" si etiquetaActor es null', () {
      final item = _item(nombreActor: 'Juan Staff');
      expect(item.lineaActor, 'Por Juan Staff');
    });

    test('null si ni etiquetaActor ni nombreActor disponibles', () {
      final item = _item();
      expect(item.lineaActor, isNull);
    });

    test('etiquetaActor vacío → usa nombreActor como fallback', () {
      final item = _item(etiquetaActor: '   ', nombreActor: 'Carlos');
      expect(item.lineaActor, 'Por Carlos');
    });

    test('nombreActor vacío → null', () {
      final item = _item(nombreActor: '');
      expect(item.lineaActor, isNull);
    });
  });

  group('ActividadMetricaItem.categoria', () {
    test('usa _categoria si se pasó al constructor', () {
      final item = ActividadMetricaItem(
        id: 'x',
        tipo: TipoActividadMetrica.asistencia,
        categoria: CategoriaActividadMetrica.invitacionQr,
        fecha: DateTime(2026),
        titulo: 'T',
        subtitulo: 'S',
        estadoLabel: 'Canjeada', // contradice la categoría pasada
        icono: Icons.qr_code,
        colorEstado: Colors.blue,
      );
      // Debe respetar el _categoria explícito, no inferir desde estadoLabel
      expect(item.categoria, CategoriaActividadMetrica.invitacionQr);
    });

    test('infiere si _categoria es null (modo legacy)', () {
      final item = ActividadMetricaItem(
        id: 'x',
        tipo: TipoActividadMetrica.asistencia,
        fecha: DateTime(2026),
        titulo: 'T',
        subtitulo: 'S',
        estadoLabel: 'Expirada',
        icono: Icons.timer_off,
        colorEstado: Colors.red,
      );
      expect(item.categoria, CategoriaActividadMetrica.listaRechazada);
    });
  });

  group('ActorMetricaOpcion.todos', () {
    test('id es null (representa todos)', () {
      expect(ActorMetricaOpcion.todos.id, isNull);
    });

    test('etiqueta es "Todos"', () {
      expect(ActorMetricaOpcion.todos.etiqueta, 'Todos');
    });
  });

  group('DatosRendimientoMetricas.vacio', () {
    test('todos los totales son 0', () {
      const d = DatosRendimientoMetricas.vacio;
      expect(d.totalTrafico, 0);
      expect(d.totalCanjesEntradas, 0);
      expect(d.totalReservas, 0);
      expect(d.totalPromosCanjeadas, 0);
      expect(d.totalVisitas, 0);
      expect(d.eventosActivos, 0);
    });

    test('todas las listas están vacías', () {
      const d = DatosRendimientoMetricas.vacio;
      expect(d.traficoPorDia, isEmpty);
      expect(d.canjesEntradasPorDia, isEmpty);
      expect(d.topEventosCanjes, isEmpty);
    });
  });
}
