library;

import 'actividad_metrica.dart';

/// Resumen de impresiones por evento (pestaña Alcance).
class EventoImpresionResumen {
  const EventoImpresionResumen({
    required this.idEvento,
    required this.titulo,
    required this.conteo,
  });

  final String idEvento;
  final String titulo;
  final int conteo;
}

/// Datos agregados para la pestaña Alcance / impresiones.
class DatosImpresionesMetricas {
  const DatosImpresionesMetricas({
    required this.seriePorDia,
    required this.totalImpresiones,
    required this.totalPerfil,
    required this.totalClicks,
    required this.eventos,
  });

  final List<PuntoRendimiento> seriePorDia;
  final int totalImpresiones;
  final int totalPerfil;
  final int totalClicks;
  final List<EventoImpresionResumen> eventos;

  static const vacio = DatosImpresionesMetricas(
    seriePorDia: [],
    totalImpresiones: 0,
    totalPerfil: 0,
    totalClicks: 0,
    eventos: [],
  );
}

/// Filtro de alcance en Métricas.
enum AlcanceFiltroTipo { todas, perfil, evento }

class AlcanceFiltroMetricas {
  const AlcanceFiltroMetricas({
    this.tipo = AlcanceFiltroTipo.todas,
    this.idEvento,
    this.etiquetaEvento,
  });

  final AlcanceFiltroTipo tipo;
  final String? idEvento;
  final String? etiquetaEvento;

  String get etiquetaUi {
    switch (tipo) {
      case AlcanceFiltroTipo.todas:
        return 'Todas las impresiones';
      case AlcanceFiltroTipo.perfil:
        return 'Visitas a mi perfil';
      case AlcanceFiltroTipo.evento:
        return etiquetaEvento ?? 'Evento';
    }
  }
}
