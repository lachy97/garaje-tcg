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

/// Id especial: todas las temporadas juntas (histórico).
const kAllSeasons = '*';

/// Selector de temporada (siempre desplegable): "Temporada T4 2026 ▾".
/// Con [allowAll] añade "Histórico" (todas las temporadas); en ese caso
/// [onChanged] recibe null.
class SeasonPicker extends StatelessWidget {
  const SeasonPicker({
    super.key,
    required this.seasons,
    required this.selected,
    required this.onChanged,
    this.allowAll = false,
    this.allSelected = false,
  });

  final List<Season> seasons;
  final Season selected;
  final ValueChanged<Season?> onChanged;
  final bool allowAll;

  /// Está elegido el histórico.
  final bool allSelected;

  @override
  Widget build(BuildContext context) {
    final label = allSelected
        ? 'Histórico · todas las temporadas'
        : 'Temporada ${seasonLabel(selected.year, selected.quarter)}';
    return Center(
      child: PopupMenuButton<String>(
        tooltip: 'Cambiar temporada',
        initialValue: allSelected ? kAllSeasons : selected.id,
        onSelected: (id) => onChanged(
            id == kAllSeasons ? null : seasons.firstWhere((s) => s.id == id)),
        itemBuilder: (_) => [
          for (final s in seasons)
            PopupMenuItem(
              value: s.id,
              child: Text('Temporada ${seasonLabel(s.year, s.quarter)}'
                  '${s.status == SeasonStatus.closed ? ' · cerrada' : ''}'),
            ),
          if (allowAll) ...[
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: kAllSeasons,
              child: Text('Histórico · todas las temporadas'),
            ),
          ],
          if (seasons.length < 2 && !allowAll)
            const PopupMenuItem(
              enabled: false,
              child: Text('Aún no hay temporadas anteriores'),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        shadows: AppColors.textGlow(blur: 8),
                      ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, color: AppColors.neon),
            ],
          ),
        ),
      ),
    );
  }
}
