/// Loader de íconos rotativos (misma idea que usuarios, para el splash).
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;

class LocalesLoader extends StatelessWidget {
  const LocalesLoader.inline({
    super.key,
    required this.size,
    required this.color,
    this.animar = true,
    this.shadows,
  });

  final double size;
  final Color color;
  final bool animar;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) {
    return _LoaderIconosAnimado(
      size: size,
      color: color,
      animar: animar,
      shadows: shadows,
    );
  }
}

class _LoaderIconosAnimado extends StatefulWidget {
  const _LoaderIconosAnimado({
    required this.size,
    required this.color,
    required this.animar,
    this.shadows,
  });

  final double size;
  final Color color;
  final bool animar;
  final List<Shadow>? shadows;

  @override
  State<_LoaderIconosAnimado> createState() => _LoaderIconosAnimadoState();
}

class _LoaderIconosAnimadoState extends State<_LoaderIconosAnimado> {
  static const _iconos = <IconData>[
    Icons.local_cafe_rounded,
    CupertinoIcons.map_fill,
    CupertinoIcons.location_fill,
    Icons.restaurant_rounded,
    CupertinoIcons.ticket_fill,
    CupertinoIcons.music_note_2,
  ];

  int _indice = 0;
  bool _loopActivo = false;

  @override
  void initState() {
    super.initState();
    if (widget.animar) _arrancarLoop();
  }

  void _arrancarLoop() {
    if (_loopActivo || !widget.animar) return;
    _loopActivo = true;
    Future.doWhile(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted || !widget.animar || !_loopActivo) {
        _loopActivo = false;
        return false;
      }
      setState(() => _indice = (_indice + 1) % _iconos.length);
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final indice = widget.animar ? _indice : 0;
    final icono = Icon(
      widget.animar ? _iconos[indice] : _iconos[0],
      key: widget.animar ? ValueKey<int>(indice) : null,
      size: widget.size,
      color: widget.color,
      shadows: widget.shadows,
    );
    if (!widget.animar) return icono;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.72, end: 1).animate(animation),
            child: child,
          ),
        );
      },
      child: icono,
    );
  }
}
