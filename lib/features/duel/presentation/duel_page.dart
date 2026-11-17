import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/common.dart';
import '../../../core/auth/account.dart';
import '../../../core/play/play.dart';
import '../../tournaments/domain/game_score.dart';
import '../../tournaments/presentation/my_table.dart';
import '../application/duel_controller.dart';
import '../domain/duel.dart';

/// Calculadora de vida con un solo teléfono en el centro de la mesa: la
/// mitad de abajo es de un jugador y la de arriba (girada) del otro. Cada
/// uno tiene sus LP, su teclado y su reloj; en el centro, deshacer, pasar el
/// turno, moneda, dado, registro y menú.
class DuelPage extends ConsumerStatefulWidget {
  const DuelPage({super.key, this.setup});

  /// Partida de un torneo (desde Mi mesa); null = duelo libre.
  final DuelSetup? setup;

  @override
  ConsumerState<DuelPage> createState() => _DuelPageState();
}

class _DuelPageState extends ConsumerState<DuelPage> {
  Timer? _tick;

  /// Ya se preguntó por este 0 (no repetir el aviso en cada redibujo).
  String? _askedZero;

  @override
  void initState() {
    super.initState();
    // Después del primer dibujo (no se puede cambiar un provider durante
    // initState).
    Future.microtask(() {
      if (mounted) ref.read(duelProvider.notifier).open(widget.setup);
    });
    // La pantalla no se apaga mientras se juega.
    WakelockPlus.enable().catchError((_) {});
    // Vertical en espejo u horizontal, según lo elegido.
    _applyOrientation(ref.read(duelLayoutProvider));
    ref.listenManual(duelLayoutProvider, (_, v) => _applyOrientation(v));
    // Relojes y tiempo de ronda.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    WakelockPlus.disable().catchError((_) {});
    // El resto de la app gira con el teléfono, como siempre.
    SystemChrome.setPreferredOrientations(const []).catchError((_) {});
    super.dispose();
  }

  void _applyOrientation(DuelLayout layout) {
    SystemChrome.setPreferredOrientations(
      layout == DuelLayout.horizontal
          ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : const [DeviceOrientation.portraitUp],
    ).catchError((_) {});
  }

  DuelController get _c => ref.read(duelProvider.notifier);

  void _act(void Function(DuelMatch m) change) {
    HapticFeedback.lightImpact();
    _c.act(change);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkZero());
  }

  /// Alguien llegó a 0: se confirma quién ganó el duelo (o se deshace).
  Future<void> _checkZero() async {
    final m = ref.read(duelProvider);
    final loser = m?.loserAtZero;
    if (m == null || loser == null || !mounted) return;
    final key = '${m.game}:${m.log.length}';
    if (_askedZero == key) return;
    _askedZero = key;
    final winner = 1 - loser;
    final ok = await confirmDialog(
      context,
      title: '${m.names[loser]} llegó a 0',
      message: '¿Gana ${m.names[winner]} el duelo ${m.game}?',
      confirm: 'Sí, gana ${m.names[winner]}',
      cancel: 'Deshacer',
    );
    if (!mounted) return;
    if (ok) {
      _endGame(winner);
    } else {
      _c.act((m) => m.undo());
    }
  }

  void _endGame(int winner) {
    _c.act((m) => m.endGame(winner));
    final m = ref.read(duelProvider)!;
    if (m.matchOver) {
      _summary();
    } else {
      _c.act((m) => m.nextGame());
      final lastLoser = winner < 0 ? null : 1 - winner;
      showMessage(
        context,
        'Duelo ${m.game}${lastLoser == null ? '' : ': ${m.names[lastLoser]} elige quién empieza'}. '
        'Toca el reloj del que empieza.',
      );
    }
  }

  // ───────────── Moneda, dado, registro, menú ─────────────

  Future<void> _coin() async {
    final r = Random().nextBool() ? 'Cara' : 'Cruz';
    _act((m) => m.note('Moneda: $r', kind: 'coin'));
    await _showRandom(icon: Icons.monetization_on_outlined, title: 'Moneda', result: r);
  }

  Future<void> _dice() async {
    final r = Random().nextInt(6) + 1;
    _act((m) => m.note('Dado: $r', kind: 'dice'));
    await _showRandom(icon: Icons.casino_outlined, title: 'Dado', result: '$r');
  }

  Future<void> _showRandom({required IconData icon, required String title, required String result}) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(icon, color: AppColors.neon),
          const SizedBox(width: 8),
          Text(title),
        ],
      ),
      content: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 600),
        curve: Curves.elasticOut,
        builder: (_, v, child) => Transform.scale(scale: 0.4 + 0.6 * v, child: child),
        child: Text(
          result,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: AppColors.neon),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Listo'))],
    ),
  );

  void _showLog() {
    final m = ref.read(duelProvider);
    if (m == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.8, child: _LogSheet(match: m)),
    );
  }

  Future<void> _menu() async {
    final m = ref.read(duelProvider);
    if (m == null) return;
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!m.matchOver) ...[
                ListTile(
                  leading: Icon(Icons.emoji_events_outlined, color: AppColors.neon),
                  title: Text('Gana el duelo ${m.game}: ${m.names[0]}'),
                  subtitle: const Text('Rendición o fin del duelo sin llegar a 0'),
                  onTap: () => Navigator.pop(ctx, 'w0'),
                ),
                ListTile(
                  leading: Icon(Icons.emoji_events_outlined, color: AppColors.neon),
                  title: Text('Gana el duelo ${m.game}: ${m.names[1]}'),
                  onTap: () => Navigator.pop(ctx, 'w1'),
                ),
                if (!m.topCut)
                  ListTile(
                    leading: const Icon(Icons.handshake_outlined),
                    title: Text('Duelo ${m.game} empatado'),
                    onTap: () => Navigator.pop(ctx, 'draw'),
                  ),
                ListTile(
                  leading: const Icon(Icons.restart_alt),
                  title: Text('LP a $kStartLp (repetir el duelo ${m.game})'),
                  onTap: () => Navigator.pop(ctx, 'reset'),
                ),
              ],
              ListTile(
                leading: const Icon(Icons.summarize_outlined),
                title: const Text('Resumen de la partida y tiempos'),
                onTap: () => Navigator.pop(ctx, 'summary'),
              ),
              if (widget.setup == null)
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Nombres de los jugadores'),
                  onTap: () => Navigator.pop(ctx, 'names'),
                ),
              // Cómo se ve: en espejo (vertical) u horizontal.
              ListTile(
                leading: Icon(
                  ref.read(duelLayoutProvider) == DuelLayout.mirror ? Icons.stay_current_landscape : Icons.flip,
                ),
                title: Text(
                  ref.read(duelLayoutProvider) == DuelLayout.mirror ? 'Ver en horizontal' : 'Ver en espejo (vertical)',
                ),
                subtitle: Text(
                  ref.read(duelLayoutProvider) == DuelLayout.mirror
                      ? 'Los dos lados de pie, uno junto al otro'
                      : 'Teléfono en el centro: la mitad de arriba girada para el rival',
                ),
                onTap: () => Navigator.pop(ctx, 'layout'),
              ),
              ListTile(
                leading: Icon(Icons.restart_alt, color: AppColors.loss),
                title: Text('Reiniciar la calculadora', style: TextStyle(color: AppColors.loss)),
                subtitle: const Text('Desde 0: LP a 8000, duelos, tiempos y registro'),
                onTap: () => Navigator.pop(ctx, 'new'),
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Salir'),
                subtitle: const Text('No se guarda nada de la partida'),
                onTap: () => Navigator.pop(ctx, 'exit'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || v == null) return;
    switch (v) {
      case 'w0':
        _endGame(0);
      case 'w1':
        _endGame(1);
      case 'draw':
        _endGame(-1);
      case 'reset':
        _act((m) => m.resetGame());
      case 'summary':
        _summary();
      case 'names':
        await _editNames(m);
      case 'exit':
        Navigator.of(context).maybePop();
      case 'layout':
        final next = ref.read(duelLayoutProvider) == DuelLayout.mirror ? DuelLayout.horizontal : DuelLayout.mirror;
        await ref.read(duelLayoutProvider.notifier).set(next);
        _applyOrientation(next);
      case 'new':
        final ok = await confirmDialog(
          context,
          title: 'Reiniciar la calculadora',
          message: 'Vuelve todo a 0: LP a $kStartLp, duelos, tiempos y registro.',
          confirm: 'Reiniciar',
          danger: true,
        );
        if (ok) _c.restart(widget.setup);
    }
  }

  Future<void> _editNames(DuelMatch m) async {
    final a = await promptText(context, title: 'Jugador de abajo', label: 'Nombre', initial: m.names[0]);
    if (a == null || !mounted) return;
    final b = await promptText(context, title: 'Jugador de arriba', label: 'Nombre', initial: m.names[1]);
    if (b == null) return;
    _c.act((m) {
      if (a.trim().isNotEmpty) m.names[0] = a.trim();
      if (b.trim().isNotEmpty) m.names[1] = b.trim();
    });
  }

  void _summary() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SummarySheet(setup: widget.setup),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(duelProvider);
    // (Otra partida en memoria: se ve la carga hasta abrir la de esta mesa.)
    if (m == null || m.matchId != widget.setup?.matchId) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final now = DateTime.now();
    final bar = _CenterBar(
      match: m,
      now: now,
      setup: widget.setup,
      onAct: _act,
      onCoin: _coin,
      onDice: _dice,
      onLog: _showLog,
      onMenu: _menu,
      onClose: () => Navigator.of(context).maybePop(),
    );
    // Horizontal: los dos lados de pie, uno junto al otro (el rival a la
    // izquierda) y la barra abajo.
    if (ref.watch(duelLayoutProvider) == DuelLayout.horizontal) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _Half(match: m, player: 1, now: now, onAct: _act),
                    ),
                    VerticalDivider(width: 1, color: AppColors.neon.withValues(alpha: 0.5)),
                    Expanded(
                      child: _Half(match: m, player: 0, now: now, onAct: _act),
                    ),
                  ],
                ),
              ),
              bar,
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // El rival, girado para que lo lea desde su lado de la mesa.
            Expanded(
              child: RotatedBox(
                quarterTurns: 2,
                child: _Half(match: m, player: 1, now: now, onAct: _act),
              ),
            ),
            bar,
            Expanded(
              child: _Half(match: m, player: 0, now: now, onAct: _act),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── Mitad de un jugador ─────────────────────────────

class _Half extends StatefulWidget {
  const _Half({required this.match, required this.player, required this.now, required this.onAct});

  final DuelMatch match;
  final int player;
  final DateTime now;
  final void Function(void Function(DuelMatch m)) onAct;

  @override
  State<_Half> createState() => _HalfState();
}

class _HalfState extends State<_Half> {
  bool _keypad = false;
  String _typed = '';

  /// Último cambio (−1800 / +500), visible unos segundos.
  int? _delta;
  Timer? _deltaTimer;

  DuelMatch get m => widget.match;
  int get p => widget.player;

  @override
  void didUpdateWidget(covariant _Half old) {
    super.didUpdateWidget(old);
    final before = old.match.lp[p];
    final after = m.lp[p];
    if (before != after) {
      // Se suma a lo que ya se estaba viendo (varios cambios seguidos).
      _delta = (_delta ?? 0) + (after - before);
      _deltaTimer?.cancel();
      _deltaTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _delta = null);
      });
    }
  }

  @override
  void dispose() {
    _deltaTimer?.cancel();
    super.dispose();
  }

  void _apply(int sign) {
    final amount = typedAmount(_typed);
    if (amount == null || amount == 0) return;
    widget.onAct((m) => m.damage(p, sign * amount));
    setState(() {
      _typed = '';
      _keypad = false;
    });
  }

  void _type(String d) {
    if (_typed.length >= 5) return;
    setState(() => _typed += d);
  }

  @override
  Widget build(BuildContext context) {
    final lp = m.lp[p];
    final active = m.active == p;
    final color = lp <= 0
        ? AppColors.loss
        : lp <= 2000
        ? AppColors.draw
        : AppColors.neon;
    return Container(
      color: active ? AppColors.neon.withValues(alpha: 0.06) : null,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          // Nombre, duelos ganados y reloj.
          Row(
            children: [
              Expanded(
                child: Text(
                  m.names[p],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              for (var i = 0; i < 2; i++)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    i < m.winsOf(p) ? Icons.star : Icons.star_border,
                    size: 18,
                    color: i < m.winsOf(p) ? AppColors.neon : AppColors.textDisabled,
                  ),
                ),
              const SizedBox(width: 8),
              _ClockPill(match: m, player: p, now: widget.now, onAct: widget.onAct),
            ],
          ),
          // LP grandes, con el último cambio al lado.
          Expanded(
            child: Center(
              child: FittedBox(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: lp.toDouble()),
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOut,
                      builder: (_, v, _) => Text(
                        '${v.round()}',
                        style: TextStyle(
                          fontSize: 88,
                          fontWeight: FontWeight.w900,
                          height: 1,
                          color: color,
                          shadows: AppColors.textGlow(color: color, blur: 14),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: _delta == null || _delta == 0 ? 0 : 1,
                      duration: const Duration(milliseconds: 250),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Text(
                          _delta == null ? '' : '${_delta! > 0 ? '+' : '−'}${_delta!.abs()}',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: (_delta ?? 0) > 0 ? AppColors.win : AppColors.loss,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Barra de LP (de 8000 a 0).
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (lp / kStartLp).clamp(0, 1).toDouble(),
              minHeight: 6,
              color: color,
              backgroundColor: AppColors.surfaceHighest,
            ),
          ),
          const SizedBox(height: 8),
          if (_keypad) _keypadView() else _quickButtons(),
        ],
      ),
    );
  }

  /// Botones rápidos en modo sumar (por defecto restan). Vuelve a restar
  /// después de cada suma.
  bool _add = false;

  Widget _quickButtons() {
    final sign = _add ? 1 : -1;
    Widget quick(String label, VoidCallback onTap, {VoidCallback? onLong}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
            foregroundColor: _add ? AppColors.win : null,
            minimumSize: const Size(0, 44),
          ),
          onPressed: onTap,
          onLongPress: onLong,
          child: FittedBox(
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
      ),
    );
    // Restar (o sumar, con el modo +) una cantidad. Mantener pulsado hace
    // lo contrario.
    Widget amount(int n) => quick('${_add ? '+' : '−'}$n', () {
      widget.onAct((m) => m.damage(p, -sign * n));
      if (_add) setState(() => _add = false);
    }, onLong: () => widget.onAct((m) => m.damage(p, sign * n)));
    return Row(
      children: [
        // − / +: cambia los botones entre restar y sumar.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: SizedBox(
            width: 44,
            child: FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
                backgroundColor: _add ? AppColors.win : AppColors.loss,
              ),
              onPressed: () => setState(() => _add = !_add),
              child: Text(_add ? '+' : '−', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            ),
          ),
        ),
        amount(50),
        amount(100),
        amount(500),
        amount(1000),
        quick('½', () => widget.onAct((m) => m.halve(p))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: SizedBox(
            width: 44,
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(44, 44), padding: EdgeInsets.zero),
              onPressed: () => setState(() => _keypad = true),
              child: const Icon(Icons.dialpad),
            ),
          ),
        ),
      ],
    );
  }

  Widget _keypadView() {
    final (typed, suffix) = typedPreview(_typed);
    Widget key(String label, VoidCallback onTap, {Color? color, bool filled = false}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: filled
            ? FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: EdgeInsets.zero,
                  backgroundColor: color,
                ),
                onPressed: onTap,
                child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              )
            : OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: EdgeInsets.zero),
                onPressed: onTap,
                child: Text(
                  label,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
                ),
              ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Lo escrito, con el "00" que se añade en gris.
        Row(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Cerrar',
              onPressed: () => setState(() {
                _keypad = false;
                _typed = '';
              }),
              icon: const Icon(Icons.close),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: typed.isEmpty ? '0' : typed),
                    TextSpan(
                      text: suffix,
                      style: TextStyle(color: AppColors.textDisabled),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Borrar',
              onPressed: _typed.isEmpty ? null : () => setState(() => _typed = _typed.substring(0, _typed.length - 1)),
              onLongPress: () => setState(() => _typed = ''),
              icon: const Icon(Icons.backspace_outlined),
            ),
          ],
        ),
        Row(
          children: [
            key('1', () => _type('1')),
            key('2', () => _type('2')),
            key('3', () => _type('3')),
            key('4', () => _type('4')),
            key('5', () => _type('5')),
          ],
        ),
        Row(
          children: [
            key('6', () => _type('6')),
            key('7', () => _type('7')),
            key('8', () => _type('8')),
            key('9', () => _type('9')),
            key('0', () => _type('0')),
          ],
        ),
        Row(
          children: [
            key('− Restar', () => _apply(1), filled: true, color: AppColors.loss),
            key('+ Sumar', () => _apply(-1), filled: true),
          ],
        ),
      ],
    );
  }
}

/// Reloj de un jugador. Tocarlo: si es su turno, lo pasa al rival; si no,
/// empieza a correr el suyo (al empezar el duelo, el que empieza lo toca).
class _ClockPill extends StatelessWidget {
  const _ClockPill({required this.match, required this.player, required this.now, required this.onAct});

  final DuelMatch match;
  final int player;
  final DateTime now;
  final void Function(void Function(DuelMatch m)) onAct;

  @override
  Widget build(BuildContext context) {
    final active = match.active == player;
    final t = match.gameElapsed(player, now);
    return Material(
      color: active ? AppColors.neon : AppColors.surfaceHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: match.matchOver ? null : () => onAct((m) => active ? m.passTurn() : m.startClock(player)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? Icons.timer : Icons.timer_outlined,
                size: 18,
                color: active ? AppColors.background : AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                formatClock(t),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: active ? AppColors.background : AppColors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── Barra central ─────────────────────────────

class _CenterBar extends ConsumerWidget {
  const _CenterBar({
    required this.match,
    required this.now,
    required this.setup,
    required this.onAct,
    required this.onCoin,
    required this.onDice,
    required this.onLog,
    required this.onMenu,
    required this.onClose,
  });

  final DuelMatch match;
  final DateTime now;
  final DuelSetup? setup;
  final void Function(void Function(DuelMatch m)) onAct;
  final VoidCallback onCoin;
  final VoidCallback onDice;
  final VoidCallback onLog;
  final VoidCallback onMenu;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = match;
    final (w, d, l) = m.score;
    // Mesa y tiempo de la ronda del torneo (el mismo reloj del organizador).
    final pid = setup?.playerId;
    final table = pid == null
        ? null
        : (ref.watch(myTablesProvider(pid)).value ?? const <MyTableInfo>[])
              .where((t) => t.matchId == setup!.matchId)
              .firstOrNull;
    Widget icon(IconData i, String tip, VoidCallback? onTap, {Color? color}) => IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: tip,
      onPressed: onTap,
      icon: Icon(i, color: color),
    );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.symmetric(horizontal: BorderSide(color: AppColors.neon.withValues(alpha: 0.5))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  m.matchOver
                      ? 'Partida terminada · $w-${d > 0 ? '$d-' : ''}$l'
                      : 'Duelo ${m.game} · $w-${d > 0 ? '$d-' : ''}$l${m.turn > 0 ? ' · Turno ${m.turn}' : ''}'
                            // Qué hacer con el reloj parado.
                            '${m.clockRunning
                                ? ''
                                : m.turn == 0
                                ? ' · Toca el reloj del que empieza'
                                : ' · En pausa: toca el reloj del que juega'}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (table != null) ...[
                  Text('  ·  Mesa ${table.table ?? '?'}  ', style: TextStyle(color: AppColors.textSecondary)),
                  if (table.timerStartedAt != null)
                    RoundCountdown(
                      start: table.timerStartedAt!,
                      pausedAt: table.timerPausedAt,
                      minutes: table.roundMinutes,
                      fontSize: 13,
                    ),
                ],
              ],
            ),
          ),
          // En móviles estrechos se encoge un poco para que quepa todo.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon(Icons.undo, 'Deshacer', m.canUndo ? () => onAct((m) => m.undo()) : null),
                icon(Icons.redo, 'Rehacer', m.canRedo ? () => onAct((m) => m.redo()) : null),
                // Pasar el turno: para un reloj y arranca el otro.
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: m.matchOver
                      ? null
                      : m.clockRunning
                      ? () => onAct((m) => m.passTurn())
                      : null,
                  icon: const Icon(Icons.swap_vert),
                  label: const Text('Turno'),
                ),
                icon(
                  m.clockRunning ? Icons.pause : Icons.play_arrow,
                  m.clockRunning ? 'Pausar el reloj' : 'Toca el reloj del que juega',
                  m.clockRunning ? () => onAct((m) => m.pauseClock()) : null,
                ),
                icon(Icons.monetization_on_outlined, 'Moneda', onCoin),
                icon(Icons.casino_outlined, 'Dado', onDice),
                icon(Icons.receipt_long_outlined, 'Registro', onLog),
                icon(Icons.more_vert, 'Más', onMenu),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Registro ─────────────────────────────

class _LogSheet extends StatelessWidget {
  const _LogSheet({required this.match});

  final DuelMatch match;

  @override
  Widget build(BuildContext context) {
    final m = match;
    final entries = m.log.reversed.toList();
    String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('REGISTRO DE LA PARTIDA', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
        ),
        Expanded(
          child: entries.isEmpty
              ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'Sin cambios todavía')
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (_, i) {
                    final e = entries[i];
                    final who = e.player == null ? '' : '${m.names[e.player!]} · ';
                    final lp = e.kind == 'lp' && e.from != null && e.to != null;
                    final delta = lp ? e.to! - e.from! : 0;
                    return ListTile(
                      dense: true,
                      leading: Icon(switch (e.kind) {
                        'coin' => Icons.monetization_on_outlined,
                        'dice' => Icons.casino_outlined,
                        'game' => Icons.emoji_events_outlined,
                        'turn' => Icons.play_arrow,
                        _ => delta >= 0 ? Icons.add_circle_outline : Icons.remove_circle_outline,
                      }, color: lp ? (delta >= 0 ? AppColors.win : AppColors.loss) : AppColors.textSecondary),
                      title: Text(
                        lp ? '$who${e.from} → ${e.to}' : '$who${e.text}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: lp ? Text(e.text) : null,
                      trailing: Text(
                        'D${e.game} · ${hm(e.at)}',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ───────────────────────────── Resumen y reporte ─────────────────────────────

class _SummarySheet extends ConsumerStatefulWidget {
  const _SummarySheet({required this.setup});

  final DuelSetup? setup;

  @override
  ConsumerState<_SummarySheet> createState() => _SummarySheetState();
}

class _SummarySheetState extends ConsumerState<_SummarySheet> {
  bool _busy = false;

  Future<void> _report(DuelMatch m, (int, int, int) s) async {
    final api = ref.read(playApiProvider);
    if (api == null || m.tournamentId == null || m.matchId == null) return;
    final (w, d, l) = m.score;
    final ok = await confirmDialog(
      context,
      title:
          'Reportar ${w > l
              ? 'victoria'
              : w < l
              ? 'derrota'
              : 'empate'} $w-${d > 0 ? '$d-' : ''}$l',
      message: 'Se envía el resultado contra ${m.names[1]}: tiene que confirmarlo en su teléfono.',
      confirm: 'Reportar',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await api.report(m.tournamentId!, m.matchId!, GameScore(s.$1, s.$2, s.$3));
      ref.invalidate(myPlayProvider(m.tournamentId!));
      if (mounted) {
        Navigator.pop(context);
        showMessage(context, 'Resultado enviado: falta que tu rival lo confirme');
      }
    } on AuthException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) showMessage(context, 'No se pudo: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(duelProvider);
    if (m == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final (w, d, l) = m.score;
    final report = m.matchOver ? m.reportScore() : null;
    final canReport = report != null && m.matchId != null && ref.watch(playApiProvider) != null;
    TableRow row(List<String> cells, {bool bold = false}) => TableRow(
      children: [
        for (final c in cells)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Text(c, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w600)),
          ),
      ],
    );
    String who(int g) => g < 0 ? 'Empate' : m.names[g];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              m.matchOver ? 'PARTIDA TERMINADA' : 'PARTIDA EN JUEGO',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
            ),
            const SizedBox(height: 4),
            Text(
              '${m.names[0]} $w-${d > 0 ? '$d-' : ''}$l ${m.names[1]}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.neon),
            ),
            const SizedBox(height: 12),
            // Tiempo que jugó cada uno, por duelo y en total.
            Table(
              columnWidths: const {0: FlexColumnWidth(1.4)},
              children: [
                row(['', m.names[0], m.names[1]], bold: true),
                for (var i = 0; i < m.games.length; i++)
                  row([
                    'Duelo ${i + 1} · ${who(m.games[i])}',
                    formatClock(Duration(milliseconds: m.gameClockMs[i][0])),
                    formatClock(Duration(milliseconds: m.gameClockMs[i][1])),
                  ]),
                if (!m.matchOver)
                  row([
                    'Duelo ${m.game} (en juego)',
                    formatClock(m.gameElapsed(0, now)),
                    formatClock(m.gameElapsed(1, now)),
                  ]),
                row(['Total', formatClock(m.elapsed(0, now)), formatClock(m.elapsed(1, now))], bold: true),
              ],
            ),
            const SizedBox(height: 16),
            if (_busy)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (canReport)
                FilledButton.icon(
                  onPressed: () => _report(m, report),
                  icon: const Icon(Icons.send),
                  label: Text('Reportar $w-${d > 0 ? '$d-' : ''}$l'),
                )
              else if (m.matchOver && m.matchId != null)
                Text(
                  'Este marcador no se puede reportar desde aquí: usa "Reportar resultado" en Mi mesa.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              if (m.matchOver) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    ref.read(duelProvider.notifier).restart(widget.setup);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.fiber_new_outlined),
                  label: const Text('Reiniciar la calculadora'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
