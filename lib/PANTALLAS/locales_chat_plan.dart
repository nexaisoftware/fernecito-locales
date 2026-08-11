library;

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import '../core/servicio_planes_locales.dart';
import '../widgets/tema_locales_scope.dart';

class LocalesChatPlan extends StatefulWidget {
  const LocalesChatPlan({super.key, required this.plan});
  final PlanLocalItem plan;

  @override
  State<LocalesChatPlan> createState() => _LocalesChatPlanState();
}

class _LocalesChatPlanState extends State<LocalesChatPlan> {
  final _srv = ServicioPlanesLocales.instancia;
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  List<PlanLocalMensaje> _mensajes = const [];
  bool _cargando = true;
  bool _enviando = false;
  RealtimeChannel? _canal;

  String? get _miUid => _srv.miUid;

  @override
  void initState() {
    super.initState();
    _cargar();
    _canal = _srv.suscribirMensajes(widget.plan.id, (m) {
      if (!mounted) return;
      if (_mensajes.any((x) => x.id == m.id)) return;
      setState(() {
        if (m.idAutorLocal == _miUid || m.idAutor == _miUid) {
          final i = _mensajes.indexWhere(
            (x) => x.id < 0 && x.cuerpo == m.cuerpo,
          );
          if (i >= 0) {
            final copia = [..._mensajes];
            copia[i] = m;
            _mensajes = copia;
            return;
          }
        }
        _mensajes = [..._mensajes, m];
      });
      _bajar();
    });
  }

  @override
  void dispose() {
    final canal = _canal;
    if (canal != null) unawaited(_srv.cerrarCanal(canal));
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final mensajes = await _srv.historial(widget.plan.id);
      await _srv.marcarLeido(widget.plan.id);
      if (!mounted) return;
      setState(() {
        _mensajes = mensajes;
        _cargando = false;
      });
      _bajar();
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _bajar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _enviar() async {
    final texto = _ctrl.text.trim();
    if (texto.isEmpty || _enviando) return;
    _ctrl.clear();
    final idTemp = -DateTime.now().microsecondsSinceEpoch;
    setState(() {
      _enviando = true;
      _mensajes = [
        ..._mensajes,
        PlanLocalMensaje(
          id: idTemp,
          idAutorLocal: _miUid,
          autorTipo: 'local',
          cuerpo: texto,
          creadoEn: DateTime.now(),
        ),
      ];
    });
    _bajar();
    try {
      final idReal = await _srv.enviarMensaje(widget.plan.id, texto);
      if (!mounted) return;
      setState(() {
        final copia = [..._mensajes];
        final i = copia.indexWhere((m) => m.id == idTemp);
        if (i < 0) return;
        if (idReal == null || copia.any((m) => m.id == idReal)) {
          copia.removeAt(i);
        } else {
          copia[i] = PlanLocalMensaje(
            id: idReal,
            idAutorLocal: _miUid,
            autorTipo: 'local',
            cuerpo: texto,
            creadoEn: DateTime.now(),
          );
        }
        _mensajes = copia;
        _enviando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mensajes = _mensajes.where((m) => m.id != idTemp).toList();
        _enviando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return Scaffold(
      backgroundColor: ColoresLocales.fondoClaro,
      appBar: AppBar(
        backgroundColor: ColoresLocales.superficie,
        elevation: 0,
        leading: IconButton(
          icon: Icon(CupertinoIcons.back, color: ColoresLocales.acentoVioleta),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chat del plan',
              style: GoogleFonts.baloo2(
                fontWeight: FontWeight.w800,
                color: ColoresLocales.tituloAcento,
                fontSize: 18,
              ),
            ),
            Text(
              widget.plan.titulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.baloo2(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _mensajes.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Text(
                            'Todavía no hay mensajes. Saludá al grupo.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.baloo2(
                              fontWeight: FontWeight.w700,
                              color: ColoresLocales.textoSecundarioOnFondoClaro,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        itemCount: _mensajes.length,
                        itemBuilder: (context, i) {
                          final m = _mensajes[i];
                          if (m.esSistema) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: ColoresLocales.superficie,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    m.cuerpo,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.baloo2(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: ColoresLocales.textoOnFondoClaro,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
                          final mio = m.esLocal &&
                              (m.idAutorLocal == _miUid || m.idAutor == _miUid);
                          return Align(
                            alignment: mio
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(context).width * 0.78,
                              ),
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                              decoration: BoxDecoration(
                                color: mio
                                    ? ColoresLocales.acentoVioletaMarca
                                    : ColoresLocales.superficie,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                m.cuerpo,
                                style: GoogleFonts.baloo2(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: mio
                                      ? Colors.white
                                      : ColoresLocales.textoOnFondoClaro,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              color: ColoresLocales.superficie,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _enviar(),
                      style: GoogleFonts.baloo2(
                        fontWeight: FontWeight.w600,
                        color: ColoresLocales.textoOnFondoClaro,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Escribí al grupo…',
                        hintStyle: GoogleFonts.baloo2(
                          color: ColoresLocales.textoSecundarioOnFondoClaro,
                        ),
                        filled: true,
                        fillColor: ColoresLocales.superficieElevada,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _enviando ? null : _enviar,
                    style: IconButton.styleFrom(
                      backgroundColor: ColoresLocales.acentoVioletaMarca,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(CupertinoIcons.paperplane_fill, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
