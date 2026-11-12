import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/common.dart';
import '../../../core/auth/account.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/play/play.dart';
import '../../../core/sync/sync_service.dart';
import '../domain/game_score.dart';
import 'my_table.dart';

/// Debajo de "Mi mesa ahora": reportar el resultado (el rival lo confirma),
/// llamar al juez y retirarse del torneo.
class TableActions extends ConsumerStatefulWidget {
  const TableActions({super.key, required this.info});

  final MyTableInfo info;

  @override
  ConsumerState<TableActions> createState() => _TableActionsState();
}

class _TableActionsState extends ConsumerState<TableActions> {
  bool _busy = false;

  MyTableInfo get i => widget.info;

  Future<void> _run(Future<void> Function(PlayApi api) action, String ok) async {
    final api = ref.read(playApiProvider);
    if (api == null || _busy) return;
    setState(() => _busy = true);
    try {
      await action(api);
      HapticFeedback.selectionClick();
      if (mounted) showMessage(context, ok);
    } on ActionCancelled {
      // nada
    } on AuthException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) showMessage(context, 'No se pudo: $e', error: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(myPlayProvider(i.tournamentId));
      }
    }
  }

  /// Opciones vistas desde mí; se envían desde el jugador 1 de la mesa.
  List<(String, GameScore)> get _options {
    GameScore s(int mine, int d, int theirs) =>
        i.iAmP1 ? GameScore(mine, d, theirs) : GameScore(theirs, d, mine);
    return [
      ('Gané 2-0', s(2, 0, 0)),
      ('Gané 2-1', s(2, 0, 1)),
      if (!i.topCut) ('Empate 1-1-1', s(1, 1, 1)),
      ('Perdí 1-2', s(1, 0, 2)),
      ('Perdí 0-2', s(0, 0, 2)),
    ];
  }

  Future<void> _report() => _run((api) async {
        final picked = await showModalBottomSheet<GameScore>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Resultado contra ${i.opponent ?? 'tu rival'}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Tu rival tiene que confirmarlo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  for (final (label, score) in _options) ...[
                    OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, score),
                      child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
        );
        if (picked == null) throw const ActionCancelled();
        await api.report(i.tournamentId, i.matchId, picked);
      }, 'Resultado enviado: falta que tu rival lo confirme');

  Future<void> _judge() => _run((api) async {
        final note = await promptText(
          context,
          title: 'Llamar al juez',
          label: '¿Qué pasa? (opcional)',
          confirm: 'Llamar',
        );
        if (note == null) throw const ActionCancelled();
        await api.judge(i.tournamentId, matchId: i.matchId, note: note.trim());
      }, 'El juez ya está avisado');

  Future<void> _drop() => _run((api) async {
        final ok = await confirmDialog(
          context,
          title: 'Retirarme del torneo',
          message: 'Dejarás de jugar las rondas siguientes (drop). Esta ronda se juega o se '
              'reporta igual. El organizador lo verá al sincronizar.',
          confirm: 'Retirarme',
          danger: true,
        );
        if (!ok) throw const ActionCancelled();
        await api.drop(i.tournamentId);
      }, 'Drop enviado al organizador');

  @override
  Widget build(BuildContext context) {
    if (ref.watch(playApiProvider) == null) return const SizedBox.shrink();
    final actions = ref.watch(myPlayProvider(i.tournamentId)).value ?? const <PlayAction>[];
    final report = actions
        .where((a) => a.kind == PlayKind.report && a.matchId == i.matchId && a.status != PlayStatus.cancelled)
        .firstOrNull;
    final judge = actions.where((a) => a.kind == PlayKind.judge && a.status == PlayStatus.open).firstOrNull;
    final drop = actions.where((a) => a.kind == PlayKind.drop && a.status == PlayStatus.open).firstOrNull;
    final myPlayer = ref.watch(permissionsProvider).playerId;
    final reportedByMe = report != null && report.playerId == myPlayer;
    final noResult = i.score == null && !i.bye;

    final children = <Widget>[];
    if (_busy) {
      children.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      ));
    } else if (noResult) {
      if (report == null) {
        children.add(FilledButton.icon(
          onPressed: _report,
          icon: const Icon(Icons.edit_note),
          label: const Text('Reportar resultado'),
        ));
      } else {
        final s = report.score!;
        switch (report.status) {
          case PlayStatus.proposed when reportedByMe:
            children.add(_line('Reportaste: ${s.outcome(asP1: i.iAmP1)}. Falta que '
                '${i.opponent ?? 'tu rival'} lo confirme.', AppColors.draw));
            children.add(TextButton(onPressed: _report, child: const Text('Cambiar')));
          case PlayStatus.proposed:
            children.add(_line('${report.nickname ?? 'Tu rival'} reportó: ${s.outcome(asP1: i.iAmP1)}. '
                '¿Es correcto?', AppColors.draw));
            children.add(Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _run((api) => api.answer(report.id, ok: false),
                        'Avisado: el juez lo revisará'),
                    child: Text('No es correcto', style: TextStyle(color: AppColors.loss)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _run((api) => api.answer(report.id, ok: true), 'Resultado confirmado'),
                    child: const Text('Confirmar'),
                  ),
                ),
              ],
            ));
          case PlayStatus.confirmed:
            children.add(_line('Confirmado por los dos: ${s.outcome(asP1: i.iAmP1)}. '
                'Aparecerá cuando sincronice el organizador.', AppColors.neon));
          case PlayStatus.disputed:
            children.add(_line('Los resultados no coinciden: el juez lo revisará.', AppColors.loss));
            children.add(TextButton(onPressed: _report, child: const Text('Corregir mi resultado')));
          default:
            break;
        }
      }
    }
    if (judge != null) {
      children.add(Row(
        children: [
          Icon(Icons.campaign, size: 18, color: AppColors.draw),
          const SizedBox(width: 6),
          Expanded(child: _line('El juez está avisado.', AppColors.draw)),
          TextButton(
            onPressed: _busy ? null : () => _run((api) => api.cancel(judge.id), 'Llamada cancelada'),
            child: const Text('Cancelar'),
          ),
        ],
      ));
    }
    if (drop != null) {
      children.add(_line('Drop pedido: el organizador te retirará al sincronizar.', AppColors.draw));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...children,
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (judge == null)
                TextButton.icon(
                  onPressed: _busy ? null : _judge,
                  icon: const Icon(Icons.campaign_outlined, size: 18),
                  label: const Text('Llamar al juez'),
                ),
              PopupMenuButton<String>(
                tooltip: 'Más',
                icon: Icon(Icons.more_vert, color: AppColors.textSecondary),
                onSelected: (_) => _drop(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'drop',
                    enabled: drop == null,
                    child: const Text('Retirarme del torneo (drop)'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _line(String text, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
      );
}
