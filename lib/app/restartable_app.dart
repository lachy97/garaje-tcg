import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

/// Permite "reiniciar" la app sin cerrarla: crea de nuevo todos los providers
/// (BD, router, pantallas). Se usa tras importar una copia de seguridad.
class RestartableApp extends StatefulWidget {
  const RestartableApp({super.key});

  static VoidCallback? _restart;

  static void restart() => _restart?.call();

  @override
  State<RestartableApp> createState() => _RestartableAppState();
}

class _RestartableAppState extends State<RestartableApp> {
  Key _key = UniqueKey();

  @override
  void initState() {
    super.initState();
    RestartableApp._restart = () {
      if (mounted) setState(() => _key = UniqueKey());
    };
  }

  @override
  Widget build(BuildContext context) =>
      ProviderScope(key: _key, child: const GarajeTcgApp());
}
