/// Visor de perfil de un cliente (persona) para el local / staff.
///
/// Pantalla reutilizable estilo iOS: se abre al tocar una persona desde
/// validación de QR, listas de asistencia, etc. Muestra foto ampliable,
/// nombre, @username, edad y — si vino con un squad — los miembros del
/// squad (cada uno tocable para abrir su propio perfil).
///
/// RLS: el local/staff solo puede leer `perfiles_usuarios` de personas que
/// son "solicitantes" de su local (tienen token o están en el snapshot de un
/// token). Por eso esta pantalla se abre desde contextos donde la persona ya
/// es solicitante; las lecturas degradan con gracia si el RLS las bloquea.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants.dart';
import '../core/servicio_reportes.dart';
import '../core/supabase_client.dart';
import '../widgets/tema_locales_scope.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Resuelve un `foto_perfil_url` que puede ser una URL completa o un path del
/// bucket `avatars`.
String _resolverFotoUrl(String? fotoPath) {
  if (fotoPath == null || fotoPath.trim().isEmpty) return '';
  final p = fotoPath.trim();
  if (p.startsWith('http')) return p;
  return ServicioSupabase().cliente.storage.from('avatars').getPublicUrl(p);
}

String? _nombreDesde(Map<String, dynamic>? m) {
  if (m == null) return null;
  final nombre = m['nombre']?.toString().trim() ?? '';
  if (nombre.isNotEmpty) return nombre;
  final username = m['username']?.toString().trim() ?? '';
  if (username.isNotEmpty) return username;
  return null;
}

int? _edadDesde(dynamic raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '');
}

/// Perfil mínimo para renderizar un miembro de squad.
class _MiembroSquad {
  final String id;
  final String? nombre;
  final String? username;
  final String fotoUrl;
  const _MiembroSquad({
    required this.id,
    this.nombre,
    this.username,
    this.fotoUrl = '',
  });
}

// ─── Pantalla principal ──────────────────────────────────────────────────────

class LocalesPerfilClientes extends StatefulWidget {
  /// Id del usuario a mostrar. Si es null, se intenta leer de los argumentos
  /// de ruta (`ModalRoute.settings.arguments`).
  final String? idUsuario;

  /// Datos opcionales para mostrar al instante mientras se carga el perfil.
  final String? nombreInicial;
  final String? usernameInicial;
  final int? edadInicial;
  final String? fotoInicial;

  /// Squad con el que vino la persona (UIDs de los miembros, del snapshot).
  final List<String> miembrosSquadUids;
  final String? nombreSquad;

  const LocalesPerfilClientes({
    super.key,
    this.idUsuario,
    this.nombreInicial,
    this.usernameInicial,
    this.edadInicial,
    this.fotoInicial,
    this.miembrosSquadUids = const [],
    this.nombreSquad,
  });

  /// Abre el visor con una transición estilo iOS.
  static Future<void> abrir(
    BuildContext context, {
    required String idUsuario,
    String? nombreInicial,
    String? usernameInicial,
    int? edadInicial,
    String? fotoInicial,
    List<String> miembrosSquadUids = const [],
    String? nombreSquad,
  }) {
    return Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => LocalesPerfilClientes(
          idUsuario: idUsuario,
          nombreInicial: nombreInicial,
          usernameInicial: usernameInicial,
          edadInicial: edadInicial,
          fotoInicial: fotoInicial,
          miembrosSquadUids: miembrosSquadUids,
          nombreSquad: nombreSquad,
        ),
      ),
    );
  }

  @override
  State<LocalesPerfilClientes> createState() => _LocalesPerfilClientesState();
}

class _LocalesPerfilClientesState extends State<LocalesPerfilClientes> {
  String? _idUsuario;
  bool _cargando = true;
  bool _argsLeidos = false;

  String? _nombre;
  String? _username;
  int? _edad;
  String _fotoUrl = '';

  List<_MiembroSquad> _miembros = const [];

  @override
  void initState() {
    super.initState();
    _idUsuario = widget.idUsuario;
    _nombre = widget.nombreInicial;
    _username = widget.usernameInicial;
    _edad = widget.edadInicial;
    _fotoUrl = _resolverFotoUrl(widget.fotoInicial);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsLeidos) return;
    _argsLeidos = true;
    // Soporte para apertura por ruta nombrada con arguments.
    if (_idUsuario == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String && args.trim().isNotEmpty) {
        _idUsuario = args.trim();
      } else if (args is Map) {
        final id = args['id_usuario']?.toString().trim();
        if (id != null && id.isNotEmpty) _idUsuario = id;
      }
    }
    _cargar();
  }

  Future<void> _cargar() async {
    final id = _idUsuario;
    if (id == null || id.isEmpty) {
      if (mounted) setState(() => _cargando = false);
      return;
    }
    final sb = ServicioSupabase().cliente;

    // Perfil principal.
    try {
      final perfil = await sb
          .from('perfiles_usuarios')
          .select('nombre, username, edad, foto_perfil_url')
          .eq('id', id)
          .maybeSingle();
      if (perfil != null) {
        final m = Map<String, dynamic>.from(perfil as Map);
        _nombre = _nombreDesde(m) ?? _nombre;
        _username = m['username']?.toString().trim() ?? _username;
        _edad = _edadDesde(m['edad']) ?? _edad;
        final url = _resolverFotoUrl(m['foto_perfil_url']?.toString());
        if (url.isNotEmpty) _fotoUrl = url;
      }
    } catch (e) {
      debugPrint('⚠️ perfil_clientes: no se pudo cargar perfil $id: $e');
    }

    // Miembros del squad (si vino con uno).
    final uids = widget.miembrosSquadUids
        .where((u) => u.trim().isNotEmpty && u != id)
        .toSet()
        .toList();
    if (uids.isNotEmpty) {
      try {
        final data = await sb
            .from('perfiles_usuarios')
            .select('id, nombre, username, foto_perfil_url')
            .inFilter('id', uids);
        final lista = <_MiembroSquad>[];
        for (final raw in (data as List).cast<Map<String, dynamic>>()) {
          final mid = raw['id']?.toString() ?? '';
          if (mid.isEmpty) continue;
          lista.add(
            _MiembroSquad(
              id: mid,
              nombre: _nombreDesde(raw),
              username: raw['username']?.toString().trim(),
              fotoUrl: _resolverFotoUrl(raw['foto_perfil_url']?.toString()),
            ),
          );
        }
        // Conservar el orden original de uids.
        lista.sort((a, b) => uids.indexOf(a.id).compareTo(uids.indexOf(b.id)));
        _miembros = lista;
      } catch (e) {
        debugPrint('⚠️ perfil_clientes: no se pudieron cargar miembros: $e');
      }
    }

    if (mounted) setState(() => _cargando = false);
  }

  void _abrirFoto() {
    if (_fotoUrl.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => _VisorFotoFullscreen(
          url: _fotoUrl,
          heroTag: 'perfil_foto_${_idUsuario ?? ''}',
        ),
      ),
    );
  }

  Future<void> _reportarUsuario() async {
    final id = _idUsuario;
    if (id == null || id.isEmpty) return;
    final motivo = await showCupertinoModalPopup<MotivoReporte>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Reportar usuario'),
        message: const Text('Elegí el motivo principal del reporte.'),
        actions: motivosReporteCuenta
            .map(
              (m) => CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(ctx, m),
                child: Text(m.label),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
      ),
    );
    if (motivo == null) return;
    final res = await ServicioReportes().reportarCuenta(
      reportanteTipo: 'local',
      targetTipo: 'usuario',
      targetId: id,
      motivo: motivo.codigo,
    );
    if (!mounted) return;
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Reporte enviado'),
        content: Text(
          res['ok'] == true
              ? 'Gracias. Vamos a revisar este usuario.'
              : (res['error']?.toString() ?? 'No se pudo enviar el reporte.'),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final nombre = (_nombre ?? '').trim();
    final username = (_username ?? '').trim();
    final tituloAppBar = nombre.isNotEmpty
        ? nombre
        : (username.isNotEmpty ? '@$username' : 'Perfil');

    return Scaffold(
      backgroundColor: ColoresLocales.fondoClaro,
      appBar: AppBar(
        backgroundColor: ColoresLocales.fondoClaro,
        elevation: 0,
        surfaceTintColor: ColoresLocales.fondoClaro,
        centerTitle: true,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).maybePop(),
          child: Icon(
            CupertinoIcons.chevron_back,
            color: ColoresLocales.acentoVioleta,
          ),
        ),
        title: Text(
          tituloAppBar,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w900,
            color: ColoresLocales.acentoVioleta,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _idUsuario == null ? null : _reportarUsuario,
            child: Text(
              'Reportar',
              style: GoogleFonts.baloo2(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: ColoresLocales.textoSecundario,
              ),
            ),
          ),
        ],
      ),
      body: (_idUsuario == null || _idUsuario!.isEmpty)
          ? _estadoVacio()
          : _contenido(nombre, username),
    );
  }

  Widget _estadoVacio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.person_crop_circle,
              size: 52,
              color: ColoresLocales.acentoVioleta.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Seleccioná una persona',
              style: GoogleFonts.baloo2(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: ColoresLocales.textoOnFondoClaro,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tocá una foto o un nombre en una lista o validación para ver su perfil.',
              textAlign: TextAlign.center,
              style: GoogleFonts.baloo2(
                fontSize: 13.5,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contenido(String nombre, String username) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const SizedBox(height: 8),
        Center(child: _avatarGrande()),
        const SizedBox(height: 18),
        if (nombre.isNotEmpty)
          Text(
            nombre,
            textAlign: TextAlign.center,
            style: GoogleFonts.baloo2(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: ColoresLocales.textoOnFondoClaro,
            ),
          ),
        if (username.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            '@$username',
            textAlign: TextAlign.center,
            style: GoogleFonts.baloo2(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: ColoresLocales.textoSecundarioOnFondoClaro,
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (_edad != null) _chipsInfo(),
        if (_cargando) ...[
          const SizedBox(height: 24),
          Center(
            child: CupertinoActivityIndicator(
              color: ColoresLocales.acentoVioleta,
            ),
          ),
        ],
        if (_miembros.isNotEmpty) ...[
          const SizedBox(height: 28),
          _seccionSquad(),
        ],
      ],
    );
  }

  Widget _avatarGrande() {
    const double size = 132;
    final inner = _fotoUrl.isEmpty
        ? Icon(
            CupertinoIcons.person_fill,
            size: 58,
            color: ColoresLocales.acentoVioleta.withOpacity(0.5),
          )
        : Hero(
            tag: 'perfil_foto_${_idUsuario ?? ''}',
            child: Image.network(
              _fotoUrl,
              fit: BoxFit.cover,
              width: size,
              height: size,
              loadingBuilder: (ctx, child, progress) => progress == null
                  ? child
                  : ColoredBox(color: ColoresLocales.cardLavanda),
              errorBuilder: (_, __, ___) => Icon(
                CupertinoIcons.person_fill,
                size: 58,
                color: ColoresLocales.acentoVioleta.withOpacity(0.5),
              ),
            ),
          );

    return GestureDetector(
      onTap: _fotoUrl.isEmpty ? null : _abrirFoto,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ColoresLocales.cardLavanda,
          border: Border.all(
            color: ColoresLocales.acentoVioleta.withOpacity(0.25),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: ColoresLocales.acentoVioleta.withOpacity(0.12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: inner,
      ),
    );
  }

  Widget _chipsInfo() {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_edad != null) _chip(CupertinoIcons.gift, '$_edad años'),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: ColoresLocales.superficie,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ColoresLocales.acentoVioleta.withOpacity(0.16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: ColoresLocales.acentoVioleta),
          const SizedBox(width: 6),
          Text(
            texto,
            style: GoogleFonts.baloo2(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: ColoresLocales.textoOnFondoClaro,
            ),
          ),
        ],
      ),
    );
  }

  Widget _seccionSquad() {
    final nombreSquad = (widget.nombreSquad ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              CupertinoIcons.person_2_fill,
              size: 18,
              color: ColoresLocales.acentoVioleta,
            ),
            const SizedBox(width: 8),
            Text(
              nombreSquad.isNotEmpty ? 'Squad · $nombreSquad' : 'Su squad',
              style: GoogleFonts.baloo2(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: ColoresLocales.textoOnFondoClaro,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: ColoresLocales.acentoVioleta.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_miembros.length}',
                style: GoogleFonts.baloo2(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: ColoresLocales.acentoVioleta,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ..._miembros.map(_filaMiembro),
      ],
    );
  }

  Widget _filaMiembro(_MiembroSquad m) {
    final nombre = (m.nombre ?? '').trim();
    final username = (m.username ?? '').trim();
    final titulo = nombre.isNotEmpty
        ? nombre
        : (username.isNotEmpty ? '@$username' : 'Usuario');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => LocalesPerfilClientes.abrir(
            context,
            idUsuario: m.id,
            nombreInicial: m.nombre,
            usernameInicial: m.username,
            fotoInicial: m.fotoUrl,
          ),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: ColoresLocales.superficie,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: ColoresLocales.acentoVioleta.withOpacity(0.12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ColoresLocales.cardLavanda,
                    border: Border.all(
                      color: ColoresLocales.acentoVioleta.withOpacity(0.2),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: m.fotoUrl.isEmpty
                      ? Icon(
                          CupertinoIcons.person_fill,
                          size: 22,
                          color: ColoresLocales.acentoVioleta.withOpacity(0.55),
                        )
                      : Image.network(
                          m.fotoUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (ctx, child, progress) =>
                              progress == null
                              ? child
                              : ColoredBox(color: ColoresLocales.cardLavanda),
                          errorBuilder: (_, __, ___) => Icon(
                            CupertinoIcons.person_fill,
                            size: 22,
                            color: ColoresLocales.acentoVioleta.withOpacity(
                              0.55,
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.baloo2(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: ColoresLocales.textoOnFondoClaro,
                        ),
                      ),
                      if (nombre.isNotEmpty && username.isNotEmpty)
                        Text(
                          '@$username',
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
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 18,
                  color: ColoresLocales.acentoVioleta.withOpacity(0.45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Visor de foto fullscreen con zoom ───────────────────────────────────────

class _VisorFotoFullscreen extends StatelessWidget {
  final String url;
  final String heroTag;
  const _VisorFotoFullscreen({required this.url, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Hero(
                    tag: heroTag,
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      loadingBuilder: (ctx, child, progress) => progress == null
                          ? child
                          : const Center(
                              child: CupertinoActivityIndicator(
                                color: Colors.white,
                              ),
                            ),
                      errorBuilder: (_, __, ___) => const Icon(
                        CupertinoIcons.exclamationmark_triangle,
                        color: Colors.white54,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.of(context).maybePop(),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.xmark,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
