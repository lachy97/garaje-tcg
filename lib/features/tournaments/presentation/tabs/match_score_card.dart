import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../app/widgets/common.dart';
import '../../../../core/db/app_database.dart';
import '../../application/tournament_service.dart';
import '../../domain/game_score.dart';

/// Tarjeta de un match con el reporte de un toque:
///
///   Jugador1        vs        Jugador2
///   [2-0] [2-1] [Empate] [1-2] [0-2]
///        [ID]   [Doble derrota]
///
/// Los marcadores se leen desde el Jugador 1 (izquierda): "2-1" = gana J1 2-1,
/// "1-2" = gana J2 2-1. Cada botón guarda el resultado al instante (sin aviso);
/// para corregir basta tocar otro botón o "Borrar resultado".
class MatchScoreCard extends ConsumerStatefulWidget {
  const MatchScoreCard({
    super.key,
    required this.match,
    required this.phase,
    required this.names,
    required this.deckNames,
    required this.editable,
    this.canClear = true,
    this.compact = false,
    this.onToggle,
    this.highlightPlayerId,
  });

  /// Una sola línea (mesa con resultado o solo consulta). Al tocarla se
  /// abre si se puede editar.
  final bool compact;

  /// Abrir (en una línea) o plegar (abierta y con resultado).
  final VoidCallback? onToggle;

  /// Jugador a resaltar (el del teléfono, en la vista de jugador).
  final String? highlightPlayerId;

  final Match match;
  final RoundPhase phase;
  final Map<String, String> names;
  final Map<String, String> deckNames;
  final bool editable;

  /// "Borrar resultado" (dejar pendiente): solo en la ronda actual.
  final bool canClear;

  @override
  ConsumerState<MatchScoreCard> createState() => _MatchScoreCardState();
}

/// Un botón de resultado.
enum _Pick { p1Clean, p1Close, draw, p2Close, p2Clean, intentionalDraw, doubleLoss }

extension on _Pick {
  String get label => switch (this) {
        _Pick.p1Clean => '2-0',
        _Pick.p1Close => '2-1',
        _Pick.draw => 'Empate',
        _Pick.p2Close => '1-2',
        _Pick.p2Clean => '0-2',
        _Pick.intentionalDraw => 'ID (empate acordado)',
        _Pick.doubleLoss => 'Doble derrota',
      };

  GameScore? get score => switch (this) {
        _Pick.p1Clean => const GameScore(2, 0, 0),
        _Pick.p1Close => const GameScore(2, 0, 1),
        _Pick.draw => const GameScore(1, 1, 1),
        _Pick.p2Close => const GameScore(1, 0, 2),
        _Pick.p2Clean => const GameScore(0, 0, 2),
        _Pick.intentionalDraw => GameScore.intentionalDraw,
        _Pick.doubleLoss => null,
      };
}

class _MatchScoreCardState extends ConsumerState<MatchScoreCard> {
  /// Evita dobles toques mientras se guarda.
  bool _saving = false;

  Match get m => widget.match;
  bool get _isTopCut => widget.phase == RoundPhase.topCut;

  /// Botón que corresponde al resultado guardado (null = pendiente).
  _Pick? get _saved {
    if (!m.result.isReported) return null;
    if (m.result == MatchResult.doubleLoss) return _Pick.doubleLoss;
    final s = GameScore(m.games1 ?? 0, m.gamesDraw ?? 0, m.games2 ?? 0);
    if (m.result == MatchResult.draw && s.gamesPlayed == 0) return _Pick.intentionalDraw;
    for (final p in _Pick.values) {
      if (p.score == s && s.result == m.result) return p;
    }
    return null;
  }

  String _describe(_Pick p, String p1, String p2) => switch (p) {
        _Pick.p1Clean || _Pick.p1Close => 'Gana $p1 ${p.label}',
        _Pick.p2Clean || _Pick.p2Close => 'Gana $p2 ${p.score!.p2}-${p.score!.p1}',
        _Pick.draw => 'Empate 1-1-1',
        _Pick.intentionalDraw => 'Empate intencional (ID)',
        _Pick.doubleLoss => 'Doble derrota (pierden los dos)',
      };

  Future<void> _pick(_Pick pick) async {
    if (_saving || pick == _saved) return;
    final matchId = m.id;
    final service = ref.read(tournamentServiceProvider);
    HapticFeedback.selectionClick();
    setState(() => _saving = true);
    await runGuarded(context, () async {
      switch (pick) {
        case _Pick.doubleLoss:
          await service.reportDoubleLoss(matchId);
        case _Pick.intentionalDraw:
          await service.reportIntentionalDraw(matchId);
        default:
          await service.reportScore(matchId, pick.score!);
      }
    });
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _clear() async {
    final ok = await confirmDialog(
      context,
      title: 'Borrar resultado',
      message: 'El match ${_savedLabel()} volverá a quedar pendiente.',
      confirm: 'Borrar',
      danger: true,
    );
    if (!ok || !mounted) return;
    await runGuarded(context, () => ref.read(tournamentServiceProvider).clearResult(m.id));
  }

  String _savedLabel() => switch (_saved) {
        _Pick.doubleLoss => '0-0-0 (doble derrota)',
        _Pick.intentionalDraw => 'ID (empate acordado)',
        _ => m.games1 == null ? '' : '${m.games1}-${m.gamesDraw ?? 0}-${m.games2 ?? 0}',
      };

  @override
  Widget build(BuildContext context) {
    final p1 = widget.names[m.player1Id] ?? '?';
    final p2 = m.player2Id == null ? null : widget.names[m.player2Id] ?? '?';

    if (m.isBye) {
      return widget.compact
          ? _CompactRow(
              table: 'BYE',
              p1: p1,
              p2: null,
              score: '2-0',
              p1Wins: true,
              p2Wins: false,
              mine: widget.highlightPlayerId == m.player1Id,
            )
          : _ByeCard(name: p1, deck: widget.deckNames[m.deck1Id]);
    }

    if (widget.compact) {
      final reported = m.result.isReported;
      final score = !reported
          ? null
          : switch (_saved) {
              _Pick.doubleLoss => 'DD',
              _Pick.intentionalDraw => 'ID',
              _ => '${m.games1 ?? 0}-${m.games2 ?? 0}${(m.gamesDraw ?? 0) > 0 ? '-${m.gamesDraw}' : ''}',
            };
      return _CompactRow(
        table: m.isThirdPlace
            ? '3º'
            : _isTopCut
                ? 'M${m.tableNumber ?? ''}'
                : '${m.tableNumber ?? ''}',
        p1: p1,
        p2: p2,
        score: score,
        p1Wins: m.result == MatchResult.p1Win,
        p2Wins: m.result == MatchResult.p2Win,
        danger: m.result == MatchResult.doubleLoss,
        extra: m.extraMinutes > 0 ? '+${m.extraMinutes}' : null,
        mine: widget.highlightPlayerId != null &&
            (widget.highlightPlayerId == m.player1Id || widget.highlightPlayerId == m.player2Id),
        onTap: widget.editable ? widget.onToggle : null,
      );
    }

    final saved = _saved;
    final reported = m.result.isReported;
    final p1Wins = m.result == MatchResult.p1Win;
    final p2Wins = m.result == MatchResult.p2Win;
    final isDoubleLoss = m.result == MatchResult.doubleLoss;
    final status = !reported
        ? (widget.editable
            ? ('Pendiente', AppColors.textSecondary)
            : ('Sin resultado', AppColors.textDisabled))
        : saved == null
            ? ('Guardado: ${_savedLabel()}', AppColors.textSecondary)
            : (
                _describe(saved, p1, p2!),
                isDoubleLoss
                    ? AppColors.loss
                    : (p1Wins || p2Wins)
                        ? AppColors.neon
                        : AppColors.draw,
              );
    final title = '${m.isThirdPlace ? '3ER PUESTO' : _isTopCut ? 'MATCH ${m.tableNumber ?? ''}' : 'MESA ${m.tableNumber ?? ''}'}'
        '${m.extraMinutes > 0 ? ' · +${m.extraMinutes} MIN' : ''}';
    final enabled = widget.editable && !_saving;

    Widget button(_Pick p) => _ResultButton(
          label: p.label,
          semanticLabel: _describe(p, p1, p2!),
          selected: saved == p,
          danger: p == _Pick.doubleLoss,
          onTap: enabled ? () => _pick(p) : null,
        );

    return Semantics(
      container: true,
      label: '${title.toLowerCase()}: $p1 contra $p2. ${status.$1}',
      child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDoubleLoss
              ? AppColors.loss
              : reported
                  ? AppColors.neon
                  : AppColors.outline,
          width: reported ? 1.2 : 0.8,
        ),
        boxShadow: reported && !isDoubleLoss ? AppColors.glow(strength: 0.5) : null,
      ),
      child: Column(
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _PlayerHeader(
                  name: p1,
                  deck: widget.deckNames[m.deck1Id],
                  highlight: p1Wins,
                ),
              ),
              SizedBox(
                width: 36,
                child: Text('vs',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: _PlayerHeader(
                  name: p2!,
                  deck: widget.deckNames[m.deck2Id],
                  highlight: p2Wins,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          if (widget.editable) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: button(_Pick.p1Clean)),
                const SizedBox(width: 6),
                Expanded(child: button(_Pick.p1Close)),
                if (!_isTopCut) ...[
                  const SizedBox(width: 6),
                  Expanded(flex: 2, child: button(_Pick.draw)),
                ] else
                  const SizedBox(width: 18),
                const SizedBox(width: 6),
                Expanded(child: button(_Pick.p2Close)),
                const SizedBox(width: 6),
                Expanded(child: button(_Pick.p2Clean)),
              ],
            ),
            if (!_isTopCut) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: button(_Pick.intentionalDraw)),
                  const SizedBox(width: 6),
                  Expanded(child: button(_Pick.doubleLoss)),
                ],
              ),
            ],
          ],
          const SizedBox(height: 8),
          Text(
            status.$1,
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700, color: status.$2),
          ),
          if (m.standingsResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'En la clasificación del torneo cuenta: '
                '${_overrideLabel(m.standingsResult!, p1, p2 ?? '')}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.draw),
              ),
            ),
          if (widget.editable && reported)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.canClear)
                  TextButton.icon(
                    onPressed: enabled ? _clear : null,
                    icon: Icon(Icons.undo, size: 18, color: AppColors.loss),
                    label: Text('Borrar resultado',
                        style: TextStyle(color: AppColors.loss, fontSize: 12)),
                  ),
                if (widget.onToggle != null)
                  TextButton.icon(
                    onPressed: widget.onToggle,
                    icon: const Icon(Icons.expand_less, size: 18),
                    label: const Text('Plegar', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
        ],
      ),
    ),
    );
  }
}

/// Botón de resultado (mínimo 48 dp de alto para tocarlo sin fallar).
class _ResultButton extends StatelessWidget {
  const _ResultButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.semanticLabel,
    this.danger = false,
  });

  final String label;

  /// Lo que lee el lector de pantalla (p. ej. "Gana Ana 2-1").
  final String semanticLabel;
  final bool selected;
  final bool danger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = danger ? AppColors.loss : AppColors.neon;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
      color: selected ? accent.withValues(alpha: 0.18) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected
              ? accent
              : enabled
                  ? AppColors.outline
                  : AppColors.textDisabled.withValues(alpha: 0.4),
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: selected
                        ? accent
                        : enabled
                            ? AppColors.textPrimary
                            : AppColors.textDisabled,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}

class _PlayerHeader extends StatelessWidget {
  const _PlayerHeader({
    required this.name,
    required this.deck,
    required this.highlight,
    this.alignEnd = false,
  });

  final String name;
  final String? deck;
  final bool highlight;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: TextStyle(
            fontSize: 16,
            fontWeight: highlight ? FontWeight.w900 : FontWeight.w600,
            color: highlight ? AppColors.neon : AppColors.textPrimary,
            shadows: highlight ? AppColors.textGlow(blur: 8) : null,
          ),
        ),
        Text(
          deck ?? 'Sin mazo',
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _ByeCard extends StatelessWidget {
  const _ByeCard({required this.name, this.deck});

  final String name;
  final String? deck;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outline, width: 0.8),
      ),
      child: Row(
        children: [
          Expanded(child: _PlayerHeader(name: name, deck: deck, highlight: true)),
          Text('BYE · 2-0-0',
              style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.neon)),
        ],
      ),
    );
  }
}

/// Texto del resultado fijado para la clasificación (distinto del real).
String _overrideLabel(MatchResult r, String p1, String p2) => switch (r) {
      MatchResult.p1Win => 'gana $p1',
      MatchResult.p2Win => 'gana $p2',
      MatchResult.draw => 'empate',
      MatchResult.doubleLoss => 'doble derrota',
      MatchResult.pending => 'sin resultado',
    };

/// Mesa en una línea: "3  Dante  2-1  Leo  ✓".
class _CompactRow extends StatelessWidget {
  const _CompactRow({
    required this.table,
    required this.p1,
    required this.p2,
    required this.score,
    required this.p1Wins,
    required this.p2Wins,
    this.danger = false,
    this.extra,
    this.mine = false,
    this.onTap,
  });

  final String table;
  final String p1;
  final String? p2;

  /// null = sin resultado.
  final String? score;
  final bool p1Wins;
  final bool p2Wins;
  final bool danger;

  /// Tiempo extra ("+5").
  final String? extra;

  /// Mesa del jugador de este teléfono.
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    TextStyle name(bool win) => TextStyle(
          fontSize: 14,
          fontWeight: win ? FontWeight.w800 : FontWeight.w500,
          color: win ? AppColors.neon : AppColors.textPrimary,
        );
    final done = score != null;
    return Semantics(
      button: onTap != null,
      label: 'mesa $table: $p1 contra ${p2 ?? 'BYE'}. ${score ?? 'Sin resultado'}',
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        decoration: BoxDecoration(
          color: mine ? AppColors.neon.withValues(alpha: 0.10) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: mine
                ? AppColors.neon
                : danger
                    ? AppColors.loss.withValues(alpha: 0.6)
                    : AppColors.outline,
            width: mine ? 1.2 : 0.8,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(table,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textSecondary)),
                    ),
                    Expanded(
                      child: Text(p1,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: name(p1Wins)),
                    ),
                    Container(
                      width: 56,
                      alignment: Alignment.center,
                      child: Text(
                        score ?? '–',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: danger
                              ? AppColors.loss
                              : done
                                  ? AppColors.textPrimary
                                  : AppColors.textDisabled,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(p2 ?? 'BYE',
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: p2 == null
                              ? TextStyle(fontSize: 14, color: AppColors.textSecondary)
                              : name(p2Wins)),
                    ),
                    if (extra != null) ...[
                      const SizedBox(width: 6),
                      Text(extra!,
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.draw)),
                    ],
                    if (onTap != null) ...[
                      const SizedBox(width: 6),
                      Icon(done ? Icons.check_circle : Icons.expand_more,
                          size: 18, color: done ? AppColors.leaf : AppColors.textSecondary),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
