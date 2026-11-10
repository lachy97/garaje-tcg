import 'package:flutter/material.dart';

import '../../app/widgets/common.dart';

/// Lo que se ve en lugar de algo que el rol o la licencia no permiten.
class LockedFeature extends StatelessWidget {
  const LockedFeature({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  /// Estadísticas que requieren licencia.
  const LockedFeature.license({super.key, this.title = 'Necesitas licencia activa'})
      : subtitle = 'Las estadísticas de todos los mazos son para quien tiene la '
            'licencia mensual. El ranking y la tier list son para todos.';

  @override
  Widget build(BuildContext context) =>
      EmptyState(icon: Icons.lock_outline, title: title, subtitle: subtitle);
}
