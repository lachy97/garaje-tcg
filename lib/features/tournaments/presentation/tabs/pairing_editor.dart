import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../app/widgets/common.dart';
import '../../../../core/db/app_database.dart';
import '../../application/tournament_service.dart';
import '../providers.dart';

/// Abre el editor de cruces de la ronda actual.
Future<void> openPairingEditor(
  BuildContext context, {
  required Round round,
  required Map<String, String> names,
}) {
  return Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _PairingEditorPage(round: round, names: names),
  ));
}

/// Emparejamiento manual: se toca un jugador y luego otro de otra mesa para
/// intercambiarlos. Solo mesas sin resultado (el BYE se puede intercambiar).
class _PairingEditorPage extends ConsumerStatefulWidget {
  const _PairingEditorPage({required this.round, required this.names});

  final Round round;
  final Map<String, String> names;

  @override
  ConsumerState<_PairingEditorPage> createState() => _PairingEditorPageState();
}

class _PairingEditorPageState extends ConsumerState<_PairingEditorPage> {
  /// Jugador elegido: (id del match, 1 o 2).
  (String, int)? _picked;
  bool _busy = false;

  bool _locked(Match m) => !m.isBye && m.result.isReported;

  Future<void> _tap(Match m, int slot) async {
    if (_busy || _locked(m)) return;
    final picked = _picked;
    if (picked == null) {
      setState(() => _picked = (m.id, slot));
      return;
    }
    if (picked.$1 == m.id) {
      // Misma mesa: se cambia la selección (o se quita si es el mismo).
      setState(() => _picked = picked.$2 == slot ? null : (m.id, slot));
      return;
    }
    setState(() => _busy = true);
    List<String> warnings = const [];
    final ok = await runGuarded(context, () async {
      warnings = await ref.read(tournamentServiceProvider).swapPlayers(
            matchIdA: picked.$1,
            slotA: picked.$2,
            matchIdB: m.id,
            slotB: slot,
            names: widget.names,
          );
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      _picked = null;
    });
    if (ok) {
      showMessage(
        context,
        warnings.isEmpty ? 'Cruce cambiado' : 'Cruce cambiado. Ojo: ${warnings.join(' · ')}',
        error: warnings.isNotEmpty,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = ref.watch(roundMatchesProvider(widget.round.id));
    return Scaffold(
      appBar: AppBar(title: Text('CAMBIAR CRUCES · RONDA ${widget.round.number}')),
      body: AsyncView(
        value: matches,
        builder: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(
                'Toca un jugador y luego otro de otra mesa para intercambiarlos. '
                'Las mesas con resultado no se pueden cambiar (borra antes el resultado).',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
            for (final m in list) _table(m),
          ],
        ),
      ),
    );
  }

  Widget _table(Match m) {
    final locked = _locked(m);
    Widget player(int slot) {
      final id = slot == 1 ? m.player1Id : m.player2Id;
      if (id == null) {
        return const _Chip(label: 'BYE', selected: false, enabled: false, onTap: null);
      }
      final selected = _picked == (m.id, slot);
      return _Chip(
        label: widget.names[id] ?? '?',
        selected: selected,
        enabled: !locked && !_busy,
        onTap: () => _tap(m, slot),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(m.isBye ? '—' : '${m.tableNumber ?? ''}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          ),
          Expanded(child: player(1)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('vs', style: TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(child: player(2)),
          SizedBox(
            width: 28,
            child: locked
                ? const Icon(Icons.lock_outline, size: 18, color: AppColors.textDisabled)
                : null,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.neon.withValues(alpha: 0.2) : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? AppColors.neon : AppColors.outline,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: !enabled
                      ? AppColors.textDisabled
                      : selected
                          ? AppColors.neon
                          : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
