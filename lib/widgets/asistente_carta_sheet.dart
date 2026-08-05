/// Asistente IA para cargar/actualizar la carta del local.
///
/// Flujo tipo bot: el local elige como cargar la carta, la IA arma un borrador
/// y el local confirma antes de guardar. No escribe directo en DB sin revision.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import '../core/servicio_edges_eventos.dart';
import '../core/supabase_client.dart';

const _kVioleta = Color(0xFF7C3AED);
const _kDorado = Color(0xFFFFD166);
const _kMaxImagenes = 3; // por tanda; se acumula subiendo más

Future<bool?> abrirAsistenteCartaLocal(
  BuildContext context, {
  int cartaItemsPrevios = 0,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => AsistenteCartaSheet(cartaItemsPrevios: cartaItemsPrevios),
  );
}

class CartaItemDraft {
  CartaItemDraft({
    required this.categoria,
    required this.nombre,
    this.descripcion = '',
    this.precio,
    this.precioHasta,
    this.moneda = 'ARS',
    this.tipoPrecio = 'fijo',
    this.tags = const [],
    this.destacado = false,
    this.confidence,
  });

  String categoria;
  String nombre;
  String descripcion;
  double? precio;
  double? precioHasta;
  String moneda;
  String tipoPrecio;
  List<String> tags;
  bool destacado;
  double? confidence;

  CartaItemDraft copia() => CartaItemDraft(
    categoria: categoria,
    nombre: nombre,
    descripcion: descripcion,
    precio: precio,
    precioHasta: precioHasta,
    moneda: moneda,
    tipoPrecio: tipoPrecio,
    tags: List<String>.from(tags),
    destacado: destacado,
    confidence: confidence,
  );

  factory CartaItemDraft.fromMap(Map<String, dynamic> map) {
    double? n(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '');
    }

    return CartaItemDraft(
      categoria: (map['categoria'] ?? 'Otros').toString(),
      nombre: (map['nombre'] ?? '').toString(),
      descripcion: (map['descripcion'] ?? '').toString(),
      precio: n(map['precio']),
      precioHasta: n(map['precio_hasta']),
      moneda: (map['moneda'] ?? 'ARS').toString(),
      tipoPrecio: (map['tipo_precio'] ?? 'fijo').toString(),
      tags: map['tags'] is List
          ? (map['tags'] as List).map((e) => e.toString()).toList()
          : const [],
      destacado: map['destacado'] == true,
      confidence: n(map['confidence']),
    );
  }

  Map<String, dynamic> toMap() => {
    'categoria': categoria.trim(),
    'nombre': nombre.trim(),
    'descripcion': descripcion.trim().isEmpty ? null : descripcion.trim(),
    'precio': precio,
    'precio_hasta': precioHasta,
    'moneda': moneda.trim().isEmpty ? 'ARS' : moneda.trim().toUpperCase(),
    'tipo_precio': tipoPrecio.trim().isEmpty ? 'fijo' : tipoPrecio.trim(),
    'tags': tags,
    'destacado': destacado,
    'confidence': confidence,
  };
}

class AsistenteCartaSheet extends StatefulWidget {
  const AsistenteCartaSheet({super.key, this.cartaItemsPrevios = 0});

  /// Cantidad de items que el local ya tiene en su carta. Si es > 0 el bot
  /// arranca ofreciendo actualizar por texto o rehacer desde cero.
  final int cartaItemsPrevios;

  @override
  State<AsistenteCartaSheet> createState() => _AsistenteCartaSheetState();
}

class _AsistenteCartaSheetState extends State<AsistenteCartaSheet> {
  final _mensajes = <_MensajeCarta>[];
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _picker = ImagePicker();

  String _paso = 'elegir';
  String _modo = 'texto';
  String _origen = 'ia_texto';
  bool _botEscribiendo = false;
  bool _procesando = false;
  bool _guardando = false;
  bool _esFlujoImagenes = false; // permite acumular fotos de a 3 por tanda
  List<CartaItemDraft> _items = [];
  List<String> _advertencias = [];

  bool get _tieneCarta => widget.cartaItemsPrevios > 0;

  @override
  void initState() {
    super.initState();
    _arrancar();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _arrancar() async {
    if (_tieneCarta) {
      setState(() => _paso = 'menu_existente');
      await _bot(
        'Hola! Tu local ya tiene una carta cargada (${widget.cartaItemsPrevios} ${widget.cartaItemsPrevios == 1 ? 'ítem' : 'ítems'}) 📋',
      );
      await _bot('¿Qué querés hacer?');
      return;
    }
    await _bot(
      'Hola! Vamos a agregar tu carta en 2 minutos ✨\n\nTu carta es clave para que los usuarios decidan mejor al salir, y para que nuestra IA tenga mejores referencias cuando alguien busque por precio, merienda, cena, tragos o promos.',
    );
    await _bot(
      'Como queres cargar tu carta? Elegi una opcion abajo y te voy guiando paso a paso 👇',
    );
  }

  void _scrollAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _bot(String texto) async {
    setState(() => _botEscribiendo = true);
    _scrollAlFinal();
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    setState(() {
      _botEscribiendo = false;
      _mensajes.add(_MensajeCarta.bot(texto));
    });
    _scrollAlFinal();
  }

  void _usuario(String texto) {
    setState(() => _mensajes.add(_MensajeCarta.usuario(texto)));
    _scrollAlFinal();
  }

  void _usuarioWidget(Widget child) {
    setState(() => _mensajes.add(_MensajeCarta.usuarioWidget(child)));
    _scrollAlFinal();
  }

  Future<void> _elegirMetodo(String paso) async {
    if (_procesando) return;
    setState(() {
      _paso = paso;
      _modo = paso == 'url' ? 'url' : 'texto';
      _items = [];
      _advertencias = [];
    });
    if (paso == 'archivo') {
      _usuario('Subir PDF o imagenes');
      await _bot(
        'Excelente 🙌 Vamos a cargarla desde tus archivos.\n\nSi tenes un PDF, subi ese archivo. Si tenes capturas o fotos de la carta, podes elegir varias imagenes juntas y yo las uno en una carta digital ordenada.',
      );
    } else if (paso == 'url') {
      _usuario('Pegar URL de carta');
      await _bot(
        'Perfecto 🔗 Pegame el link publico de tu carta.\n\nOjo: links de edicion de Canva no se pueden leer desde la IA. Si es Canva, exportalo como PDF o imagen y subilo aca.',
      );
      _inputFocus.requestFocus();
    } else {
      _usuario('Escribir en lenguaje natural');
      await _bot(
        'Joya ✍️ Escribime la carta como te salga. Por ejemplo:\n\nHamburguesa doble 12000\nPinta 3500\nMerienda para dos 15000\n\nYo la ordeno por categorias y vos revisas antes de guardar.',
      );
      _inputFocus.requestFocus();
    }
  }

  Future<void> _procesarTexto() async {
    final texto = _input.text.trim();
    if (texto.length < 8 || _procesando) return;
    _input.clear();
    _usuario(texto.length > 220 ? '${texto.substring(0, 220)}...' : texto);
    await _procesar(modo: 'texto', texto: texto);
  }

  Future<void> _procesarUrl() async {
    if (_procesando) return;
    final url = _input.text.trim();
    if (!url.startsWith('http')) {
      await _bot('Ese link no parece válido 🔗 Pegá la URL completa (arranca con http…).');
      return;
    }
    _input.clear();
    _usuario(url);
    await _procesar(modo: 'url', url: url);
  }

  Future<void> _procesarActualizar() async {
    final texto = _input.text.trim();
    if (texto.length < 4 || _procesando) return;
    _input.clear();
    _usuario(texto.length > 220 ? '${texto.substring(0, 220)}...' : texto);
    await _procesar(modo: 'actualizar', texto: texto);
  }

  Future<void> _elegirPdf() async {
    if (_procesando) return;
    try {
      // withData:true trae los bytes en web y nativo. (NO usar withReadStream:
      // en web deja file.bytes en null y el flujo se cortaba sin aviso.)
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return; // canceló
      final file = result.files.first;
      if (!file.name.toLowerCase().endsWith('.pdf')) {
        await _bot('Ese archivo no es un PDF 📄 Elegí el PDF de tu carta, o probá con imágenes.');
        return;
      }
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        await _bot('No pude leer ese PDF 😕 Probá descargarlo al dispositivo y subirlo de nuevo, o mandá fotos de la carta.');
        return;
      }
      if (bytes.length > 48 * 1024 * 1024) {
        await _bot('Ese PDF pesa más de 48 MB 📄 Probá con uno más liviano o subí fotos de la carta.');
        return;
      }
      _usuarioWidget(_PdfSeleccionado(nombre: file.name, bytes: bytes.length));
      setState(() => _procesando = true);
      await _bot('Subiendo tu PDF... 📤');
      final path = await _subirIngesta(file.name, bytes);
      if (path == null) {
        if (mounted) setState(() => _procesando = false);
        await _bot('No pude subir el PDF 😕 Revisá tu conexión y probá de nuevo.');
        return;
      }
      await _procesar(modo: 'archivo_storage', archivoPath: path, archivoNombre: file.name);
    } catch (e) {
      if (mounted) setState(() => _procesando = false);
      await _bot('No pude abrir el archivo 😕 Probá de nuevo, o cargá la carta como imágenes o texto.');
    }
  }

  /// Sube un archivo temporal al bucket privado `cartas_ingest/{uid}/...`.
  /// El edge lo lee con signed URL y lo borra al terminar. Devuelve el path.
  Future<String?> _subirIngesta(String nombre, Uint8List bytes, {int indice = 0, int? ts}) async {
    final uid = ServicioSupabase().usuarioActual?.id;
    if (uid == null) return null;
    final low = nombre.toLowerCase();
    final ext = low.endsWith('.pdf')
        ? 'pdf'
        : low.endsWith('.png')
            ? 'png'
            : 'jpg';
    final marca = ts ?? DateTime.now().millisecondsSinceEpoch;
    final path = '$uid/ingesta_${marca}_$indice.$ext';
    await ServicioSupabase().cliente.storage.from('cartas_ingest').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: _mime(nombre), upsert: true),
        );
    return path;
  }

  Future<void> _elegirImagenes() async {
    if (_procesando) return;
    try {
      // Downscale en el picker (funciona en web y nativo) → payload chico y
      // request estable. La carta se lee igual de bien a 1500px.
      final fotos = await _picker.pickMultiImage(imageQuality: 60, maxWidth: 1500);
      if (fotos.isEmpty) return;
      final seleccionadas = fotos.take(_kMaxImagenes).toList();
      final previews = <Uint8List>[];
      final nombres = <String>[];
      final listaBytes = <Uint8List>[];
      for (final foto in seleccionadas) {
        final bytes = await foto.readAsBytes();
        if (bytes.length > 20 * 1024 * 1024) {
          await _bot('Una foto pesa más de 20 MB 📷 Probá con una captura más liviana.');
          return;
        }
        listaBytes.add(bytes);
        previews.add(bytes);
        nombres.add(foto.name);
      }
      _usuarioWidget(_ImagenesSeleccionadas(bytes: previews, nombres: nombres));
      if (fotos.length > _kMaxImagenes) {
        await _bot('Subo de a $_kMaxImagenes fotos por tanda para que salga estable. Tomé estas $_kMaxImagenes y al terminar podés seguir agregando más de la misma carta.');
      }
      setState(() {
        _procesando = true;
        _esFlujoImagenes = true;
      });
      await _bot('Subiendo tus fotos... 📤');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final paths = <String>[];
      for (var i = 0; i < seleccionadas.length; i++) {
        // ts único por tanda para no pisar archivos de tandas anteriores.
        final p = await _subirIngesta(seleccionadas[i].name, listaBytes[i], indice: i, ts: ts);
        if (p != null) paths.add(p);
      }
      if (paths.isEmpty) {
        if (mounted) setState(() => _procesando = false);
        await _bot('No pude subir las fotos 😕 Revisá tu conexión y probá de nuevo.');
        return;
      }
      await _procesar(modo: 'imagenes_storage', imagenesPaths: paths, acumular: true);
    } catch (e) {
      if (mounted) setState(() => _procesando = false);
      await _bot('No pude abrir tus fotos 😕 Probá de nuevo, o cargá la carta como PDF o texto.');
    }
  }

  Future<void> _procesar({
    required String modo,
    String? texto,
    String? url,
    String? archivoDataUri,
    String? archivoNombre,
    List<String>? imagenesDataUri,
    String? archivoPath,
    List<String>? imagenesPaths,
    bool acumular = false,
  }) async {
    setState(() {
      _procesando = true;
      _advertencias = [];
      if (!acumular) _items = [];
    });
    await _bot(
      modo == 'actualizar'
          ? 'Dame un segundo, aplico los cambios a tu carta... 🧑‍🍳'
          : 'Dame unos segundos, estoy leyendo y ordenando tu carta... 🧑‍🍳',
    );
    try {
      final data = await ServicioEdgesEventos().asistenteCartaLocal(
        accion: 'parsear',
        modo: modo,
        texto: texto,
        url: url,
        archivoDataUri: modo == 'archivo' ? archivoDataUri : null,
        imagenDataUri: modo == 'imagen' ? archivoDataUri : null,
        imagenesDataUri: modo == 'imagenes' ? imagenesDataUri : null,
        archivoPath: modo == 'archivo_storage' ? archivoPath : null,
        imagenesPaths: modo == 'imagenes_storage' ? imagenesPaths : null,
        archivoNombre: archivoNombre,
      );
      final rawItems = data['items'] is List ? data['items'] as List : const [];
      final items = rawItems
          .whereType<Map>()
          .map((e) => CartaItemDraft.fromMap(Map<String, dynamic>.from(e)))
          .where((e) => e.nombre.trim().isNotEmpty)
          .toList();
      final advertencias = data['advertencias'] is List
          ? (data['advertencias'] as List).map((e) => e.toString()).toList()
          : <String>[];
      final previos = _items.length;
      setState(() {
        // 'actualizar' devuelve la carta COMPLETA ya modificada → reemplaza.
        // Fotos por tanda → se suman a lo que ya venía.
        _items = (acumular && modo != 'actualizar') ? [..._items, ...items] : items;
        _advertencias = advertencias;
        _origen = switch (modo) {
          'url' => 'ia_url',
          'archivo' || 'archivo_storage' => 'ia_archivo',
          'imagen' || 'imagenes' || 'imagenes_storage' => 'ia_imagen',
          _ => 'ia_texto',
        };
      });
      if (items.isEmpty && !acumular) {
        final mensaje = advertencias.isNotEmpty
            ? '${advertencias.first}\n\nTambien podes pegar la carta como texto: producto + precio, uno por linea.'
            : 'No pude detectar productos claros 😅 Proba pegando la carta con nombre + precio, o subi una imagen/PDF mas legible.';
        await _bot(mensaje);
      } else if (items.isEmpty && acumular) {
        // Tanda de fotos que no aportó nada: conservamos lo anterior.
        final aviso = advertencias.isNotEmpty ? '${advertencias.first}\n\n' : '';
        await _bot('${aviso}Esas fotos no me sumaron productos nuevos 😅 Probá con capturas más nítidas, o guardá lo que ya tenés (${_items.length} ítems).');
        _refrescarPreview();
      } else {
        if (modo == 'actualizar') {
          await _bot('Listo! Actualicé tu carta ✨ Quedó con ${_items.length} ítems. Revisá la vista previa y guardá los cambios.');
        } else if (acumular && previos > 0) {
          await _bot('Sumé ${items.length} ítems 🎉 Van ${_items.length} en total. Podés agregar más fotos de la misma carta o guardar.');
        } else {
          await _bot('Listo! Encontre ${items.length} items 🎉\n\nRevisa la vista previa, toca cualquier item para editarlo y despues guardamos la carta.');
        }
        _refrescarPreview();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _procesando = false);
      final esTimeout = e is EdgeException &&
          (e.code == 'edge_timeout' || e.code == 'network_error');
      await _bot(
        esTimeout
            ? 'Tardó demasiado ⏳ Suele pasar con PDFs o fotos pesadas. Probá con menos imágenes, una foto más nítida y liviana, o pegá la carta como texto.'
            : 'No pude leer la carta ahora 😕 Probá de nuevo en un momento, o cargala de otra forma (texto, imágenes o PDF).',
      );
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  /// Deja una sola vista previa siempre al final del chat (evita duplicar el
  /// bloque cuando se suman más tandas de fotos o se actualiza).
  void _refrescarPreview() {
    setState(() {
      _mensajes.removeWhere((m) => m.tipo == _MensajeTipo.preview);
      _mensajes.add(_MensajeCarta.preview());
    });
    _scrollAlFinal();
  }

  Future<void> _guardar() async {
    if (_guardando || _items.isEmpty) return;
    final validos = _items
        .where(
          (e) => e.nombre.trim().isNotEmpty && e.categoria.trim().isNotEmpty,
        )
        .map((e) => e.toMap())
        .toList();
    if (validos.isEmpty) return;
    setState(() => _guardando = true);
    try {
      final res = await ServicioEdgesEventos().asistenteCartaLocal(
        accion: 'guardar',
        items: validos,
        origen: _origen,
      );
      if (!mounted) return;
      final cantidad = res['cantidad'] is int ? res['cantidad'] as int : validos.length;
      setState(() => _guardando = false);
      await _bot('✅ ¡Carta guardada! Cargué $cantidad ítems. Ya la ven tus clientes y la IA la usa para recomendarte por precio.');
      await Future<void>.delayed(const Duration(milliseconds: 750));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      final detalle = e is EdgeException
          ? (e.detail?.trim().isNotEmpty == true ? e.detail!.trim() : e.mensaje.trim())
          : '';
      final extra = detalle.isNotEmpty ? '\n\n($detalle)' : '';
      await _bot('No pude guardar la carta 😕 Revisá tu conexión y tocá "Guardar carta" de nuevo. Tus ítems siguen acá, no se perdió nada.$extra');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  String _mime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    return 'text/plain';
  }

  void _editarItem(CartaItemDraft item) {
    final categoriaCtrl = TextEditingController(text: item.categoria);
    final nombreCtrl = TextEditingController(text: item.nombre);
    final descCtrl = TextEditingController(text: item.descripcion);
    final precioCtrl = TextEditingController(
      text: item.precio?.toStringAsFixed(0) ?? '',
    );
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: Text(
          'Editar item',
          style: GoogleFonts.baloo2(fontWeight: FontWeight.w900),
        ),
        message: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              _campoMini(categoriaCtrl, 'Categoria'),
              const SizedBox(height: 8),
              _campoMini(nombreCtrl, 'Nombre'),
              const SizedBox(height: 8),
              _campoMini(
                precioCtrl,
                'Precio ARS',
                keyboard: TextInputType.number,
              ),
              const SizedBox(height: 8),
              _campoMini(descCtrl, 'Descripcion breve', maxLines: 2),
            ],
          ),
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              setState(() {
                item.categoria = categoriaCtrl.text.trim();
                item.nombre = nombreCtrl.text.trim();
                item.descripcion = descCtrl.text.trim();
                item.precio = double.tryParse(
                  precioCtrl.text.replaceAll(',', '.'),
                );
              });
              Navigator.pop(context);
            },
            child: const Text('Aplicar'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ),
    );
  }

  Widget _campoMini(
    TextEditingController ctrl,
    String hint, {
    int maxLines = 1,
    TextInputType? keyboard,
  }) {
    return CupertinoTextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboard,
      placeholder: hint,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ColoresLocales.superficieElevada,
        borderRadius: BorderRadius.circular(12),
      ),
      style: GoogleFonts.baloo2(
        color: ColoresLocales.textoOnFondoClaro,
        fontWeight: FontWeight.w700,
      ),
      placeholderStyle: GoogleFonts.baloo2(
        color: ColoresLocales.textoSecundarioOnFondoClaro,
      ),
    );
  }

  String _precio(CartaItemDraft item) {
    if (item.precio == null) return 'Consultar';
    final p = item.precio!.round().toString();
    if (item.tipoPrecio == 'desde') return 'Desde \$$p';
    if (item.tipoPrecio == 'rango' && item.precioHasta != null) {
      return '\$$p - \$${item.precioHasta!.round()}';
    }
    return '\$$p';
  }

  Future<void> _confirmarCerrar() async {
    if (_procesando || _guardando) return;
    if (_items.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    final salir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ColoresLocales.superficie,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('¿Salir sin guardar?',
            style: GoogleFonts.baloo2(color: ColoresLocales.textoOnFondoClaro, fontWeight: FontWeight.w800)),
        content: Text(
          'Tenés una carta lista sin guardar. Si salís, la perdés y hay que cargarla de nuevo.',
          style: GoogleFonts.baloo2(color: ColoresLocales.textoSecundarioOnFondoClaro, height: 1.3),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Seguir acá', style: GoogleFonts.baloo2(color: _kVioleta, fontWeight: FontWeight.w800)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Salir', style: GoogleFonts.baloo2(color: ColoresLocales.textoSecundarioOnFondoClaro)),
          ),
        ],
      ),
    );
    if (salir == true && mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmarCerrar();
      },
      child: DraggableScrollableSheet(
        initialChildSize: 0.94,
        minChildSize: 0.62,
        maxChildSize: 0.97,
        expand: false,
        builder: (_, _) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: ColoresLocales.degradadoHome,
            stops: const [0.0, 0.25, 0.6, 1.0],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            _header(),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                itemCount: _mensajes.length + (_botEscribiendo ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i >= _mensajes.length) return const _TypingBurbuja();
                  final msg = _mensajes[i];
                  if (msg.tipo == _MensajeTipo.preview) return _previewCarta();
                  if (msg.tipo == _MensajeTipo.widget) {
                    return Align(
                      alignment: msg.esBot
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: msg.child ?? const SizedBox.shrink(),
                    );
                  }
                  return _TextoBurbuja(texto: msg.texto, esBot: msg.esBot);
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: viewInsets),
              child: _AreaInput(child: _buildInput()),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _header() {
    return Container(
      decoration: BoxDecoration(
        color: ColoresLocales.superficie,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _kVioleta,
            ),
            child: const Icon(
              CupertinoIcons.sparkles,
              size: 19,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Asistente de carta',
                  style: GoogleFonts.baloo2(
                    color: ColoresLocales.textoOnFondoClaro,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                Text(
                  'Precios claros para vender mas',
                  style: GoogleFonts.baloo2(
                    color: ColoresLocales.textoSecundarioOnFondoClaro,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _confirmarCerrar,
            icon: const Icon(CupertinoIcons.xmark),
            color: ColoresLocales.textoSecundarioOnFondoClaro,
          ),
        ],
      ),
    );
  }

  Widget _buildInput() {
    if (_procesando) {
      return const _EstadoProcesando(texto: 'Procesando carta...');
    }
    if (_items.isNotEmpty) return _accionesResultado();
    if (_paso == 'menu_existente') return _accionesMenuExistente();
    if (_paso == 'actualizar') return _inputActualizar();
    if (_paso == 'elegir') return _accionesMetodo();
    if (_paso == 'archivo') return _accionesArchivo();
    return _inputTextoUrl();
  }

  Widget _accionesMenuExistente() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BotonAccion(
          texto: 'Actualizar precios / productos',
          icono: CupertinoIcons.pencil,
          primario: true,
          onTap: () async {
            _usuario('Actualizar precios / productos');
            setState(() {
              _paso = 'actualizar';
              _modo = 'actualizar';
            });
            await _bot(
              'Dale 🙌 Escribime los cambios usando el nombre lo más exacto posible para no confundir productos parecidos.\n\nEj: "subí el lomo completo a 22000, agregá una burger doble a 15000, sacá la limonada".\n\nAgarro tu carta actual, aplico los cambios y vos revisás antes de guardar.',
            );
            _inputFocus.requestFocus();
          },
        ),
        const SizedBox(height: 8),
        _BotonAccion(
          texto: 'Subir carta nueva desde 0',
          icono: CupertinoIcons.arrow_2_circlepath,
          onTap: () async {
            _usuario('Subir carta nueva desde 0');
            setState(() => _paso = 'elegir');
            await _bot(
              'Ok, arrancamos de cero. Ojo: al guardar la nueva se reemplaza la carta actual. ¿Cómo la cargás?',
            );
          },
        ),
      ],
    );
  }

  Widget _inputActualizar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _input,
            focusNode: _inputFocus,
            minLines: 1,
            maxLines: 4,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: GoogleFonts.baloo2(
              color: ColoresLocales.textoOnFondoClaro,
              fontWeight: FontWeight.w700,
            ),
            cursorColor: _kVioleta,
            decoration: InputDecoration(
              hintText: 'Ej: subí el lomo a 22000, agregá papas con cheddar 9000...',
              hintStyle: GoogleFonts.baloo2(
                color: ColoresLocales.textoSecundarioOnFondoClaro,
                fontWeight: FontWeight.w500,
              ),
              filled: true,
              fillColor: ColoresLocales.superficieElevada,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _BotonEnviar(onTap: _procesarActualizar),
      ],
    );
  }

  Widget _accionesMetodo() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BotonAccion(
          texto: 'Subir PDF / imagen',
          icono: CupertinoIcons.doc_fill,
          onTap: () => _elegirMetodo('archivo'),
          primario: true,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _BotonAccion(
                texto: 'Pegar URL',
                icono: CupertinoIcons.link,
                onTap: () => _elegirMetodo('url'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _BotonAccion(
                texto: 'Escribir carta',
                icono: CupertinoIcons.text_quote,
                onTap: () => _elegirMetodo('texto'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _accionesArchivo() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: _BotonAccion(
                texto: 'Subir imagenes',
                icono: CupertinoIcons.photo_on_rectangle,
                onTap: _elegirImagenes,
                primario: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _BotonAccion(
                texto: 'Subir PDF',
                icono: CupertinoIcons.doc_text_fill,
                onTap: _elegirPdf,
                primario: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _BotonAccion(
          texto: 'Volver',
          icono: CupertinoIcons.chevron_left,
          onTap: () => setState(() => _paso = 'elegir'),
        ),
      ],
    );
  }

  Widget _accionesResultado() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_advertencias.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _advertencias.take(2).map((e) => '• $e').join('\n'),
              style: GoogleFonts.baloo2(
                color: _kDorado,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: _esFlujoImagenes
                  ? _BotonAccion(
                      texto: 'Agregar más fotos',
                      icono: CupertinoIcons.plus_circle,
                      onTap: _guardando ? null : _elegirImagenes,
                    )
                  : _BotonAccion(
                      texto: 'Empezar de nuevo',
                      icono: CupertinoIcons.arrow_counterclockwise,
                      onTap: _guardando
                          ? null
                          : () {
                              setState(() {
                                _items = [];
                                _advertencias = [];
                                _paso = 'elegir';
                                _modo = 'texto';
                              });
                              _bot(
                                'Dale, probemos otra forma. Como queres cargar la carta?',
                              );
                            },
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _BotonAccion(
                texto: _guardando ? 'Guardando...' : 'Guardar carta',
                icono: CupertinoIcons.check_mark_circled_solid,
                onTap: _guardando ? null : _guardar,
                primario: true,
              ),
            ),
          ],
        ),
        if (_esFlujoImagenes)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Sumás de a $_kMaxImagenes fotos por vez. Cuando esté completa, tocá "Guardar carta".',
              textAlign: TextAlign.center,
              style: GoogleFonts.baloo2(
                color: ColoresLocales.textoSecundarioOnFondoClaro,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _inputTextoUrl() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _input,
            focusNode: _inputFocus,
            minLines: 1,
            maxLines: _modo == 'texto' ? 4 : 1,
            keyboardType: _modo == 'url'
                ? TextInputType.url
                : TextInputType.multiline,
            textInputAction: _modo == 'url'
                ? TextInputAction.send
                : TextInputAction.newline,
            onSubmitted: (_) {
              if (_modo == 'url') _procesarUrl();
            },
            style: GoogleFonts.baloo2(
              color: ColoresLocales.textoOnFondoClaro,
              fontWeight: FontWeight.w700,
            ),
            cursorColor: _kVioleta,
            decoration: InputDecoration(
              hintText: _modo == 'url'
                  ? 'Pega el link de tu carta...'
                  : 'Ej: hamburguesa doble \$12000, pinta \$3500...',
              hintStyle: GoogleFonts.baloo2(
                color: ColoresLocales.textoSecundarioOnFondoClaro,
                fontWeight: FontWeight.w500,
              ),
              filled: true,
              fillColor: ColoresLocales.superficieElevada,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _BotonEnviar(onTap: _modo == 'url' ? _procesarUrl : _procesarTexto),
      ],
    );
  }

  Widget _previewCarta() {
    final categorias = <String, List<CartaItemDraft>>{};
    for (final item in _items) {
      categorias.putIfAbsent(item.categoria, () => []).add(item);
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 28),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ColoresLocales.superficie,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  CupertinoIcons.list_bullet,
                  color: _kDorado,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Vista previa de carta',
                    style: GoogleFonts.baloo2(
                      color: ColoresLocales.textoOnFondoClaro,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Toca un item para editarlo. Desliza para borrar.',
              style: GoogleFonts.baloo2(
                color: ColoresLocales.textoSecundarioOnFondoClaro,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            ...categorias.entries.expand(
              (entry) => [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, top: 4),
                  child: Text(
                    entry.key,
                    style: GoogleFonts.baloo2(
                      color: _kVioleta,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
                ...entry.value.map(_itemTile),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemTile(CartaItemDraft item) {
    return Dismissible(
      key: ValueKey('${item.nombre}-${item.categoria}-${_items.indexOf(item)}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => setState(() => _items.remove(item)),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        color: const Color(0xFFEB5757),
        child: const Icon(CupertinoIcons.trash, color: Colors.white),
      ),
      child: GestureDetector(
        onTap: () => _editarItem(item),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: ColoresLocales.superficieElevada,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.nombre,
                      style: GoogleFonts.baloo2(
                        color: ColoresLocales.textoOnFondoClaro,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    if (item.descripcion.trim().isNotEmpty)
                      Text(
                        item.descripcion,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.baloo2(
                          color: ColoresLocales.textoSecundarioOnFondoClaro,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _precio(item),
                style: GoogleFonts.baloo2(
                  color: _kVioleta,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _MensajeTipo { texto, preview, widget }

class _MensajeCarta {
  const _MensajeCarta._({
    required this.texto,
    required this.esBot,
    required this.tipo,
    this.child,
  });

  factory _MensajeCarta.bot(String texto) =>
      _MensajeCarta._(texto: texto, esBot: true, tipo: _MensajeTipo.texto);
  factory _MensajeCarta.usuario(String texto) =>
      _MensajeCarta._(texto: texto, esBot: false, tipo: _MensajeTipo.texto);
  factory _MensajeCarta.usuarioWidget(Widget child) => _MensajeCarta._(
    texto: '',
    esBot: false,
    tipo: _MensajeTipo.widget,
    child: child,
  );
  factory _MensajeCarta.preview() =>
      const _MensajeCarta._(texto: '', esBot: true, tipo: _MensajeTipo.preview);

  final String texto;
  final bool esBot;
  final _MensajeTipo tipo;
  final Widget? child;
}

class _TextoBurbuja extends StatelessWidget {
  const _TextoBurbuja({required this.texto, required this.esBot});

  final String texto;
  final bool esBot;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: esBot ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: esBot ? ColoresLocales.superficie : _kVioleta,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(esBot ? 5 : 18),
            bottomRight: Radius.circular(esBot ? 18 : 5),
          ),
        ),
        child: Text(
          texto,
          style: GoogleFonts.baloo2(
            color: esBot ? ColoresLocales.textoOnFondoClaro : Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
            height: 1.18,
          ),
        ),
      ),
    );
  }
}

class _TypingBurbuja extends StatelessWidget {
  const _TypingBurbuja();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: ColoresLocales.superficie,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          'escribiendo...',
          style: GoogleFonts.baloo2(
            color: ColoresLocales.textoSecundarioOnFondoClaro,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _PdfSeleccionado extends StatelessWidget {
  const _PdfSeleccionado({required this.nombre, required this.bytes});

  final String nombre;
  final int bytes;

  String get _peso {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(bytes / 1024).round()} KB';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kVioleta,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              CupertinoIcons.doc_text_fill,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.baloo2(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                    height: 1.05,
                  ),
                ),
                Text(
                  'PDF • $_peso',
                  style: GoogleFonts.baloo2(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImagenesSeleccionadas extends StatelessWidget {
  const _ImagenesSeleccionadas({required this.bytes, required this.nombres});

  final List<Uint8List> bytes;
  final List<String> nombres;

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width * 0.78;
    return Container(
      width: ancho,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kVioleta,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            bytes.length == 1
                ? 'Imagen seleccionada'
                : '${bytes.length} imagenes seleccionadas',
            style: GoogleFonts.baloo2(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 82,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: bytes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Stack(
                    children: [
                      Image.memory(
                        bytes[i],
                        width: 68,
                        height: 82,
                        fit: BoxFit.cover,
                      ),
                      Positioned(
                        top: 5,
                        left: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: GoogleFonts.baloo2(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AreaInput extends StatelessWidget {
  const _AreaInput({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: ColoresLocales.superficie.withValues(alpha: 0.96),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _BotonAccion extends StatelessWidget {
  const _BotonAccion({
    required this.texto,
    required this.icono,
    required this.onTap,
    this.primario = false,
  });

  final String texto;
  final IconData icono;
  final VoidCallback? onTap;
  final bool primario;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: onTap == null ? 0.55 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: primario ? _kVioleta : ColoresLocales.superficieElevada,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icono,
                size: 16,
                color: primario
                    ? Colors.white
                    : ColoresLocales.textoSecundarioOnFondoClaro,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  texto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.baloo2(
                    color: primario
                        ? Colors.white
                        : ColoresLocales.textoOnFondoClaro,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BotonEnviar extends StatelessWidget {
  const _BotonEnviar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: _kDorado,
        ),
        child: const Icon(CupertinoIcons.arrow_up, color: _kVioleta, size: 24),
      ),
    );
  }
}

class _EstadoProcesando extends StatelessWidget {
  const _EstadoProcesando({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: ColoresLocales.superficieElevada,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: _kVioleta),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: GoogleFonts.baloo2(
                color: ColoresLocales.textoOnFondoClaro,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
