import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../app/widgets/common.dart';
import '../../../../core/db/app_database.dart';
import '../../application/tournament_service.dart';

/// Reloj de la ronda actual.
///
/// Solo informa al organizador: al llegar a 0 avisa (vibración + sonido +
/// mensaje), pero NO pone resultados. Los matches sin terminar se reportan a
/// mano (p. ej. con "Doble derrota").
///
/// La hora de inicio se guarda en la BD, así que el reloj sigue bien aunque
/// se cierre la app o se apague la pantalla.
class RoundTimer extends ConsumerStatefulWidget {
  const RoundTimer({super.key, required this.round, required this.minutes});

  final Round round;
  final int minutes;

  @override
  ConsumerState<RoundTimer> createState() => _RoundTimerState();
}

class _RoundTimerState extends ConsumerState<RoundTimer> {
  Timer? _ticker;
  Duration? _lastRemaining;

  Duration get _total => Duration(minutes: widget.minutes);

  Duration? get _remaining {
    final start = widget.round.timerStartedAt;
    if (start == null) return null;
    return _total - DateTime.now().difference(start);
  }

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _lastRemaining = _remaining;
  }

  @override
  void didUpdateWidget(RoundTimer old) {
    super.didUpdateWidget(old);
    if (old.round.timerStartedAt != widget.round.timerStartedAt) {
      _lastRemaining = _remaining;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final now = _remaining;
    final before = _lastRemaining;
    _lastRemaining = now;
    // Aviso solo al cruzar el 0 con la app abierta (no al volver a entrar).
    if (before != null && now != null && before > Duration.zero && now <= Duration.zero) {
      _timeUp();
    }
    setState(() {});
  }

  Future<void> _timeUp() async {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    Future.delayed(const Duration(milliseconds: 400), HapticFeedback.heavyImpact);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.alarm, color: AppColors.loss, size: 40),
        title: const Text('¡Se acabó el tiempo!'),
        content: const Text(
          'Pon los resultados de cada mesa. Si un match no terminó y '
          'pierden los dos, marca "Doble derrota".',
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
        ],
      ),
    );
  }

  Future<void> _start({required bool restart}) async {
    final service = ref.read(tournamentServiceProvider);
    if (restart) {
      final ok = await confirmDialog(
        context,
        title: 'Reiniciar tiempo',
        message: 'El reloj vuelve a ${widget.minutes}:00 desde ahora.',
        confirm: 'Reiniciar',
      );
      if (!ok || !mounted) return;
    }
    await runGuarded(context, () => service.startRoundTimer(widget.round.id));
  }

  Future<void> _stop() async {
    final ok = await confirmDialog(
      context,
      title: 'Detener tiempo',
      message: 'El reloj de esta ronda se pone a cero (sin iniciar).',
      confirm: 'Detener',
      danger: true,
    );
    if (!ok || !mounted) return;
    await runGuarded(
        context, () => ref.read(tournamentServiceProvider).stopRoundTimer(widget.round.id));
  }

  static String _fmt(Duration d) {
    final s = d.inSeconds.abs();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = (s % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '${m.toString().padLeft(2, '0')}:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining;

    if (remaining == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: OutlinedButton.icon(
          onPressed: () => _start(restart: false),
          icon: const Icon(Icons.timer_outlined),
          label: Text('Iniciar tiempo (${widget.minutes} min)'),
        ),
      );
    }

    final over = remaining <= Duration.zero;
    final lastFive = !over && remaining <= const Duration(minutes: 5);
    final color = over
        ? AppColors.loss
        : lastFive
            ? AppColors.draw
            : AppColors.neon;
    final progress = over
        ? 1.0
        : 1 - remaining.inMilliseconds / _total.inMilliseconds;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(over ? Icons.alarm : Icons.timer_outlined, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      over ? 'TIEMPO  +${_fmt(remaining)}' : _fmt(remaining),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: color,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        shadows: AppColors.textGlow(blur: 8),
                      ),
                    ),
                    Text(
                      over
                          ? 'Se acabó el tiempo: pon los resultados'
                          : 'Tiempo restante de ${widget.minutes} min',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Reiniciar tiempo',
                onPressed: () => _start(restart: true),
                icon: const Icon(Icons.restart_alt),
              ),
              IconButton(
                tooltip: 'Detener tiempo',
                onPressed: _stop,
                icon: const Icon(Icons.stop_circle_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 5,
              color: color,
              backgroundColor: AppColors.outline,
            ),
          ),
        ],
      ),
    );
  }
}
