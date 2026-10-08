import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/database_provider.dart';
import '../../../core/utils/season_utils.dart';

/// Todas las temporadas (la más reciente primero). Garantiza que exista la actual.
final seasonListProvider = StreamProvider.autoDispose<List<Season>>((ref) async* {
  final dao = ref.watch(seasonsDaoProvider);
  await dao.current();
  yield* dao.watchAll();
});

/// Temporada elegida: [selectedId] si existe, si no la del trimestre actual.
Season pickSeason(List<Season> seasons, String? selectedId) {
  final now = DateTime.now();
  return seasons.firstWhere(
    (s) => s.id == selectedId,
    orElse: () => seasons.firstWhere(
      (s) => s.year == now.year && s.quarter == quarterOf(now),
      orElse: () => seasons.first,
    ),
  );
}

/// Título "Temporada T4 2026 ▾" que abre la lista de temporadas.
/// Sirve para ver el ranking o la tier list de un trimestre ya terminado.
class SeasonPicker extends StatelessWidget {
  const SeasonPicker({
    super.key,
    required this.seasons,
    required this.selected,
    required this.onChanged,
  });

  final List<Season> seasons;
  final Season selected;
  final ValueChanged<Season> onChanged;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      'Temporada ${seasonLabel(selected.year, selected.quarter)}',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            shadows: AppColors.textGlow(blur: 8),
          ),
    );
    if (seasons.length < 2) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: title);
    }
    return Center(
      child: PopupMenuButton<Season>(
        tooltip: 'Cambiar temporada',
        initialValue: selected,
        onSelected: onChanged,
        itemBuilder: (_) => [
          for (final s in seasons)
            PopupMenuItem(
              value: s,
              child: Text('Temporada ${seasonLabel(s.year, s.quarter)}'),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: title),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, color: AppColors.neon),
            ],
          ),
        ),
      ),
    );
  }
}
