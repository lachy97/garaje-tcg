import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../app/widgets/common.dart';
import '../../../../core/db/app_database.dart';
import '../../application/tournament_service.dart';
import '../../domain/game_score.dart';

/// Tarjeta de un match con el reporte en línea:
///
///   Jugador1        vs        Jugador2
///                 Empate
///   ○ 0           ○ 0           ○ 0
///   ○ 1           ○ 1           ○ 1
///   ○ 2           ○ 2           ○ 2
///
/// Columna izquierda = juegos ganados por J1, centro = juegos empatados,
/// derecha = juegos ganados por J2. En cuanto la combinación forma un marcador
/// válido (2-0-0, 2-0-1, 0-0-2, 1-0-2, 1-1-1) se guarda sola.
class MatchScoreCard extends ConsumerStatefulWidget {
  const MatchScoreCard({
    super.key,
    required this.match,
    required this.phase,
    required this.names,
    required this.deckNames,
    required this.editable,
  });

  final Match match;
  final RoundPhase phase;
  final Map<String, String> names;
  final Map<String, String> deckNames;
  final bool editable;

  @override
  ConsumerState<MatchScoreCard> createState() => _MatchScoreCardState();
}

class _MatchScoreCardState extends ConsumerState<MatchScoreCard> {
  late int _p1;
  late int _draws;
  late int _p2;

  /// Doble derrota marcada (se acabó el tiempo y pierden los dos).
  late bool _doubleLoss;

  Match get m => widget.match;
  bool get _isTopCut => widget.phase == RoundPhase.topCut;

  @override
  void initState() {
    super.initState();
    _loadFromMatch();
  }

  @override
  void didUpdateWidget(MatchScoreCard old) {
    super.didUpdateWidget(old);
    // Solo se sincroniza desde la BD si cambia el match o llega un marcador
    // guardado distinto; al borrar el resultado se conserva la selección local.
    final changedMatch = old.match.id != m.id;
    // (solo si cambió la fila de este match, no por cambios en otras mesas)
    final saved = old.match != m &&
        m.games1 != null &&
        (m.games1 != _p1 || (m.gamesDraw ?? 0) != _draws || (m.games2 ?? 0) != _p2);
    final dl = old.match != m && (m.result == MatchResult.doubleLoss) != _doubleLoss;
    if (changedMatch || saved || dl) _loadFromMatch();
  }

  void _loadFromMatch() {
    _p1 = m.games1 ?? 0;
    _draws = m.gamesDraw ?? 0;
    _p2 = m.games2 ?? 0;
    _doubleLoss = m.result == MatchResult.doubleLoss;
  }

  GameScore get _local => GameScore(_p1, _draws, _p2);

  bool _isValid(GameScore s) => _isTopCut ? s.isValidForTopCut : s.isValid;

  /// Opciones que nunca pueden formar un marcador válido se muestran apagadas.
  bool _optionPossible(int column, int value) {
    final options = _isTopCut ? GameScore.allowedTopCut : GameScore.allowed;
    return options.any((s) => switch (column) {
          0 => s.p1 == value,
          1 => s.draws == value,
          _ => s.p2 == value,
        });
  }

  Future<void> _select(int column, int value) async {
    setState(() {
      switch (column) {
        case 0:
          _p1 = value;
        case 1:
          _draws = value;
        default:
          _p2 = value;
      }
    });
    final service = ref.read(tournamentServiceProvider);
    final score = _local;
    // Solo se guarda un marcador válido. Si la combinación no es válida, el
    // resultado guardado (si lo hay) se mantiene: borrar exige confirmación.
    if (_isValid(score)) {
      await runGuarded(context, () => service.reportScore(m.id, score));
    }
  }

  Future<void> _toggleDoubleLoss(bool? value) async {
    if (value == true) {
      if (m.result.isReported && !_doubleLoss) {
        final ok = await confirmDialog(
          context,
          title: 'Doble derrota',
          message: 'Se reemplazará el resultado ${_savedLabel()} por 0-0-0 '
              '(pierden los dos).',
          confirm: 'Aplicar',
          danger: true,
        );
        if (!ok || !mounted) return;
      }
      setState(() {
        _p1 = _draws = _p2 = 0;
        _doubleLoss = true;
      });
      await runGuarded(
          context, () => ref.read(tournamentServiceProvider).reportDoubleLoss(m.id));
    } else {
      await _clear();
    }
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
    if (mounted) {
      setState(() {
        _p1 = _draws = _p2 = 0;
        _doubleLoss = false;
      });
    }
  }

  String _savedLabel() => m.result == MatchResult.doubleLoss
      ? '0-0-0 (doble derrota)'
      : m.games1 == null
      ? ''
      : '${m.games1}-${m.gamesDraw ?? 0}-${m.games2 ?? 0}';

  @override
  Widget build(BuildContext context) {
    final p1 = widget.names[m.player1Id] ?? '?';
    final p2 = m.player2Id == null ? null : widget.names[m.player2Id] ?? '?';

    if (m.isBye) return _ByeCard(name: p1, deck: widget.deckNames[m.deck1Id]);

    final score = _local;
    final valid = _isValid(score) || _doubleLoss;
    final untouched = _p1 == 0 && _draws == 0 && _p2 == 0;
    final status = _doubleLoss
        ? ('Doble derrota · 0-0-0 (pierden los dos)', AppColors.loss)
        : _statusFor(score, valid, untouched, p1, p2!);
    final title = m.isThirdPlace
        ? '3ER PUESTO'
        : _isTopCut
            ? 'MATCH ${m.tableNumber ?? ''}'
            : 'MESA ${m.tableNumber ?? ''}';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _doubleLoss
              ? AppColors.loss
              : valid
                  ? AppColors.neon
                  : AppColors.outline,
          width: valid ? 1.2 : 0.8,
        ),
        boxShadow: valid && !_doubleLoss ? AppColors.glow(strength: 0.5) : null,
      ),
      child: Column(
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          // Cabecera: J1 | vs / Empate | J2
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _PlayerHeader(
                  name: p1,
                  deck: widget.deckNames[m.deck1Id],
                  highlight: !_doubleLoss && valid && score.p1 > score.p2,
                ),
              ),
              const SizedBox(
                width: 72,
                child: Column(
                  children: [
                    Text('vs',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                    Text('Empate',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Expanded(
                child: _PlayerHeader(
                  name: p2!,
                  deck: widget.deckNames[m.deck2Id],
                  highlight: !_doubleLoss && valid && score.p2 > score.p1,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Filas 0 / 1 / 2 con un radio por columna
          for (final value in const [0, 1, 2])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  for (final column in const [0, 1, 2])
                    Expanded(
                      child: Align(
                        alignment: switch (column) {
                          0 => Alignment.centerLeft,
                          1 => Alignment.center,
                          _ => Alignment.centerRight,
                        },
                        child: _ScoreRadio(
                          value: value,
                          selected: switch (column) {
                            0 => _p1 == value,
                            1 => _draws == value,
                            _ => _p2 == value,
                          },
                          enabled: widget.editable &&
                              !_doubleLoss &&
                              _optionPossible(column, value),
                          onTap: () => _select(column, value),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (!_isTopCut && (widget.editable || _doubleLoss))
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: widget.editable ? () => _toggleDoubleLoss(!_doubleLoss) : null,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Checkbox(
                    value: _doubleLoss,
                    onChanged: widget.editable ? _toggleDoubleLoss : null,
                    activeColor: AppColors.loss,
                    side: const BorderSide(color: AppColors.textSecondary, width: 1.5),
                  ),
                  Flexible(
                    child: Text(
                      'Doble derrota (se acabó el tiempo)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _doubleLoss ? AppColors.loss : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Text(
            status.$1,
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700, color: status.$2),
          ),
          if (!valid && !_doubleLoss && m.result.isReported)
            Text('Guardado: ${_savedLabel()}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          if (widget.editable && m.result.isReported)
            TextButton.icon(
              onPressed: _clear,
              icon: const Icon(Icons.undo, size: 18, color: AppColors.loss),
              label: const Text('Borrar resultado',
                  style: TextStyle(color: AppColors.loss, fontSize: 13)),
            ),
        ],
      ),
    );
  }

  (String, Color) _statusFor(GameScore s, bool valid, bool untouched, String p1, String p2) {
    if (valid) {
      return switch (s.result) {
        MatchResult.p1Win => ('Gana $p1 · $s', AppColors.neon),
        MatchResult.p2Win => ('Gana $p2 · $s', AppColors.neon),
        _ => ('Empate · $s', AppColors.draw),
      };
    }
    if (untouched) {
      return widget.editable
          ? ('Pendiente', AppColors.textSecondary)
          : ('Sin resultado', AppColors.textDisabled);
    }
    if (_isTopCut && s == const GameScore(1, 1, 1)) {
      return ('En el Top Cut no hay empates', AppColors.loss);
    }
    return ('Marcador incompleto o no válido ($s)', AppColors.loss);
  }
}

/// Radio redondo con número, con los colores del tema.
class _ScoreRadio extends StatelessWidget {
  const _ScoreRadio({
    required this.value,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final int value;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = !enabled && !selected
        ? AppColors.textDisabled
        : selected
            ? AppColors.neon
            : AppColors.textPrimary;
    return InkWell(
      onTap: enabled ? onTap : null,
      customBorder: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
                boxShadow: selected ? AppColors.glow(strength: 0.5) : null,
              ),
              alignment: Alignment.center,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: selected ? 13 : 0,
                height: selected ? 13 : 0,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.neon,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('$value',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: color)),
          ],
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
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
          const Text('BYE · 2-0-0',
              style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.neon)),
        ],
      ),
    );
  }
}
