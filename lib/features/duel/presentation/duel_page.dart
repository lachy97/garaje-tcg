import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/common.dart';
import '../application/duel_controller.dart';
import '../domain/duel.dart';
import '../domain/duel_visuals.dart';
import 'coin_dice.dart';

/// Colores del tema elegido para la calculadora (se fija al dibujar la
/// página; todos sus widgets lo usan).
AppPalette _pal = AppPalette.dark;

List<Shadow> _glow(Color c, double blur) =>
    _pal.isDark ? [Shadow(color: c.withValues(alpha: 0.7), blurRadius: blur)] : const [];

/// Calculadora de vida con un solo teléfono en el centro de la mesa: la
/// mitad de abajo es de un jugador y la de arriba (girada) del otro. Cada
/// lado tiene sus LP, su teclado (con moneda y dado), sus relojes (turno y
/// total) y, en la esquina, deshacer, girar ese lado (de 90 en 90°) y las
/// opciones (tema, reiniciar, registro y salir). No se guarda nada de las
/// partidas.
class DuelPage extends ConsumerStatefulWidget {
  const DuelPage({super.key, this.setup});

  /// Partida de un torneo (desde Mi mesa); null = duelo libre.
  final DuelSetup? setup;

  @override
  ConsumerState<DuelPage> createState() => _DuelPageState();
}

class _DuelPageState extends ConsumerState<DuelPage> {
  Timer? _tick;

  /// Giro de cada lado, en cuartos de vuelta (cada toque, 90° más).
  final List<int> _turns = [0, 0];

  @override
  void initState() {
    super.initState();
    // Después del primer dibujo (no se puede cambiar un provider durante
    // initState).
    Future.microtask(() {
      if (mounted) ref.read(duelProvider.notifier).open(widget.setup);
    });
    // La pantalla no se apaga mientras se juega, y queda en vertical (cada
    // lado se gira con su botón).
    WakelockPlus.enable().catchError((_) {});
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]).catchError((_) {});
    // Relojes.
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

  DuelController get _c => ref.read(duelProvider.notifier);

  void _act(void Function(DuelMatch m) change) {
    HapticFeedback.lightImpact();
    _c.act((m) {
      change(m);
      // Alguien llegó a 0: los relojes se paran.
      if (m.loserAtZero != null) m.pauseClock();
    });
  }

  /// Cuartos de vuelta con los que se ve el lado [p]: el de arriba, girado
  /// para el rival, más lo que haya girado cada uno con su botón.
  int _quarterTurns(int p) => (p == 1 ? 2 : 0) + _turns[p];

  /// Diálogo orientado hacia el jugador [p] (como se ve su lado).
  Future<T?> _dialog<T>(int p, WidgetBuilder builder) => showDialog<T>(
    context: context,
    builder: (ctx) => Theme(
      data: AppTheme.build(_pal),
      child: RotatedBox(
        quarterTurns: _quarterTurns(p) % 4,
        child: Builder(builder: builder),
      ),
    ),
  );

  // ───────────── Moneda y dado ─────────────

  Future<void> _coin(int p) async {
    final heads = Random().nextBool();
    await _rollDialog(
      p,
      title: 'Cara o cruz',
      result: heads ? 'Cara' : 'Cruz',
      icon: Icons.monetization_on_outlined,
      builder: (onDone) => CoinFlip(heads: heads, accent: _pal.neon, onDone: onDone),
      log: 'Moneda: ${heads ? 'cara' : 'cruz'}',
      kind: 'coin',
    );
  }

  Future<void> _dice(int p) async {
    final v = Random().nextInt(6) + 1;
    await _rollDialog(
      p,
      title: 'Dado',
      result: '$v',
      icon: Icons.casino_outlined,
      builder: (onDone) => DiceRoll(value: v, onDone: onDone),
      log: 'Dado: $v',
      kind: 'dice',
    );
  }

  /// La moneda o el dado ruedan 2 s; al parar se ve el resultado y queda en
  /// el registro.
  Future<void> _rollDialog(
    int p, {
    required String title,
    required String result,
    required IconData icon,
    required Widget Function(VoidCallback onDone) builder,
    required String log,
    required String kind,
  }) {
    var logged = false;
    return _dialog<void>(
      p,
      (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Row(
            children: [
              Icon(icon, color: _pal.neon),
              const SizedBox(width: 8),
              Text(title),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              builder(() {
                if (logged) return;
                logged = true;
                _act((m) => m.note(log, kind: kind));
                setLocal(() {});
              }),
              const SizedBox(height: 8),
              AnimatedOpacity(
                opacity: logged ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: Text(
                  result,
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: _pal.neon),
                ),
              ),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Listo'))],
        ),
      ),
    );
  }

  // ───────────── Opciones ─────────────

  Future<void> _menu(int p) async {
    final v = await _dialog<String>(
      p,
      (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final theme = ref.watch(duelThemeProvider);
          final pal = theme.palette;
          return Theme(
            data: AppTheme.build(pal),
            child: AlertDialog(
              contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Tema de colores (se ve al momento).
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        'TEMA',
                        style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, color: pal.textSecondary),
                      ),
                    ),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: [for (final t in DuelTheme.values) _ThemeSwatch(theme: t, selected: t == theme)],
                    ),
                    const Divider(height: 24),
                    ListTile(
                      leading: Icon(Icons.restart_alt, color: pal.loss),
                      title: Text(
                        'Reiniciar',
                        style: TextStyle(color: pal.loss, fontWeight: FontWeight.w800),
                      ),
                      subtitle: const Text('Todo al inicio: LP a 8000 y relojes a 0'),
                      onTap: () => Navigator.pop(ctx, 'reset'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: const Text('Registro de la partida'),
                      onTap: () => Navigator.pop(ctx, 'log'),
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
        },
      ),
    );
    if (!mounted || v == null) return;
    switch (v) {
      case 'reset':
        final ok = await _dialog<bool>(
          p,
          (ctx) => AlertDialog(
            title: const Text('Reiniciar'),
            content: Text('Todo vuelve al inicio: LP a $kStartLp y relojes a 0.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _pal.loss),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Reiniciar'),
              ),
            ],
          ),
        );
        if (ok == true) _c.restart(widget.setup);
      case 'log':
        final m = ref.read(duelProvider);
        if (m == null) return;
        await _dialog<void>(
          p,
          (ctx) => Dialog(
            child: SizedBox(
              width: 420,
              height: MediaQuery.sizeOf(ctx).height * 0.6,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _LogSheet(match: m),
              ),
            ),
          ),
        );
      case 'exit':
        Navigator.of(context).maybePop();
    }
  }

  Widget _half(DuelMatch m, int p, DateTime now) => _Half(
    match: m,
    player: p,
    now: now,
    onAct: _act,
    onCoin: () => _coin(p),
    onDice: () => _dice(p),
    onMenu: () => _menu(p),
    onRotate: () => setState(() => _turns[p] = (_turns[p] + 1) % 4),
  );

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(duelProvider);
    _pal = ref.watch(duelThemeProvider).palette;
    // (Otra partida en memoria: se ve la carga hasta abrir la de esta mesa.)
    if (m == null || m.matchId != widget.setup?.matchId) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final now = DateTime.now();
    // El teléfono en el centro de la mesa: el lado de arriba, girado para el
    // rival. Cada lado gira de 90 en 90° con su botón.
    return Theme(
      data: AppTheme.build(_pal),
      child: Scaffold(
        backgroundColor: _pal.background,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: RotatedBox(quarterTurns: _quarterTurns(1) % 4, child: _half(m, 1, now)),
              ),
              Divider(height: 2, thickness: 2, color: _pal.neon.withValues(alpha: 0.6)),
              Expanded(
                child: RotatedBox(quarterTurns: _quarterTurns(0) % 4, child: _half(m, 0, now)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Muestra de un tema: tocarla lo aplica.
class _ThemeSwatch extends ConsumerWidget {
  const _ThemeSwatch({required this.theme, required this.selected});

  final DuelTheme theme;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = theme.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => ref.read(duelThemeProvider.notifier).set(theme),
      child: Container(
        width: 74,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: p.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? p.neon : p.outline, width: selected ? 3 : 1),
        ),
        child: Column(
          children: [
            Text(
              '8000',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: p.neon),
            ),
            Text(theme.label, style: TextStyle(fontSize: 11, color: p.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── Lado de un jugador ─────────────────────────────

class _Half extends StatefulWidget {
  const _Half({
    required this.match,
    required this.player,
    required this.now,
    required this.onAct,
    required this.onCoin,
    required this.onDice,
    required this.onMenu,
    required this.onRotate,
  });

  final DuelMatch match;
  final int player;
  final DateTime now;
  final void Function(void Function(DuelMatch m)) onAct;
  final VoidCallback onCoin;
  final VoidCallback onDice;
  final VoidCallback onMenu;

  /// Girar este lado 90°.
  final VoidCallback onRotate;

  @override
  State<_Half> createState() => _HalfState();
}

class _HalfState extends State<_Half> {
  bool _keypad = false;
  String _typed = '';

  /// Se añaden los dos ceros a lo escrito (se quitan con el primer borrar).
  bool _zeros = true;

  /// Botones rápidos en modo sumar (por defecto restan). Vuelve a restar
  /// después de cada suma.
  bool _add = false;

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
    final amount = typedAmount(_typed, zeros: _zeros);
    if (amount == null || amount == 0) return;
    widget.onAct((m) => m.damage(p, sign * amount));
    setState(() {
      _typed = '';
      _zeros = true;
      _keypad = false;
    });
  }

  void _type(String d) {
    if (_typed.length >= 5) return;
    setState(() => _typed += d);
  }

  void _backspace() {
    final (digits, zeros) = typedBackspace(_typed, zeros: _zeros);
    setState(() {
      _typed = digits;
      _zeros = zeros;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lp = m.lp[p];
    final active = m.active == p;
    // Los LP con el color del tema (en rojo a 0); la barra, con su escala de
    // colores, igual en todos los temas.
    final color = lp <= 0 ? _pal.loss : _pal.neon;
    final bar = lifeBarColor(lp);
    return Container(
      color: active ? _pal.neon.withValues(alpha: 0.06) : null,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: Column(
        children: [
          // Relojes (turno y total) y, en la esquina, deshacer, girar y menú.
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _Clocks(match: m, player: p, now: widget.now, onAct: widget.onAct),
                ),
              ),
              _corner(Icons.undo, 'Deshacer', m.canUndo ? () => widget.onAct((m) => m.undo()) : null),
              _corner(Icons.rotate_90_degrees_cw_outlined, 'Girar este lado 90°', widget.onRotate),
              _corner(Icons.more_vert, 'Opciones', widget.onMenu),
            ],
          ),
          // LP: grandes, y más pequeños con el teclado abierto (deja sitio).
          if (_keypad) SizedBox(height: 56, child: _lp(lp, color, small: true)) else Expanded(child: _lp(lp, color)),
          // Barra de LP (de 8000 a 0).
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              // Por encima de 8000, llena (y cada vez más azul).
              value: (lp / kStartLp).clamp(0, 1).toDouble(),
              minHeight: 8,
              color: bar,
              backgroundColor: _pal.surfaceHighest,
            ),
          ),
          const SizedBox(height: 8),
          if (_keypad) Expanded(child: _keypadView()) else _quickButtons(),
        ],
      ),
    );
  }

  Widget _corner(IconData icon, String tip, VoidCallback? onTap) => IconButton(
    visualDensity: VisualDensity.compact,
    tooltip: tip,
    onPressed: onTap,
    icon: Icon(icon, color: onTap == null ? _pal.textDisabled : _pal.textSecondary),
  );

  /// Los LP con el último cambio al lado.
  Widget _lp(int lp, Color color, {bool small = false}) => Center(
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
                // Grandes: el FittedBox los ajusta al ancho que haya.
                fontSize: small ? 56 : 200,
                fontWeight: FontWeight.w900,
                height: 1,
                color: color,
                shadows: _glow(color, small ? 10 : 22),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (_delta != null && _delta != 0)
            Padding(
              padding: EdgeInsets.only(left: small ? 8 : 16),
              child: Text(
                '${_delta! > 0 ? '+' : '−'}${_delta!.abs()}',
                style: TextStyle(
                  fontSize: small ? 24 : 60,
                  fontWeight: FontWeight.w900,
                  color: _delta! > 0 ? _pal.neon : _pal.loss,
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _quickButtons() {
    final sign = _add ? 1 : -1;
    Widget quick(String label, VoidCallback onTap, {VoidCallback? onLong}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
            foregroundColor: _add ? _pal.neon : null,
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
    Widget square(Widget child, VoidCallback onTap, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        width: 44,
        child: FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
            backgroundColor: color,
          ),
          onPressed: onTap,
          child: child,
        ),
      ),
    );
    return Row(
      children: [
        // − / +: cambia los botones entre restar y sumar.
        square(
          Text(_add ? '+' : '−', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          () => setState(() => _add = !_add),
          color: _add ? _pal.neon : _pal.loss,
        ),
        amount(50),
        amount(100),
        amount(500),
        amount(1000),
        quick('½', () => widget.onAct((m) => m.halve(p))),
        square(const Icon(Icons.dialpad), () => setState(() => _keypad = true)),
      ],
    );
  }

  /// Teclado: 1–9 en 3 columnas, una cuarta fila con moneda, 0 y dado, y
  /// abajo Restar / Sumar.
  Widget _keypadView() {
    final (typed, suffix) = typedPreview(_typed, zeros: _zeros);
    Widget key(Widget child, VoidCallback onTap, {Color? color, bool filled = false}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: SizedBox.expand(
          child: filled
              ? FilledButton(
                  style: FilledButton.styleFrom(padding: EdgeInsets.zero, backgroundColor: color),
                  onPressed: onTap,
                  child: FittedBox(child: child),
                )
              : OutlinedButton(
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: color),
                  onPressed: onTap,
                  child: FittedBox(child: child),
                ),
        ),
      ),
    );
    Widget digit(String d) =>
        key(Text(d, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)), () => _type(d));
    return Column(
      children: [
        // Lo escrito, con el "00" que se añade en gris.
        SizedBox(
          height: 40,
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Cerrar',
                onPressed: () => setState(() {
                  _keypad = false;
                  _typed = '';
                  _zeros = true;
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
                        style: TextStyle(color: _pal.textDisabled),
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
                onPressed: _typed.isEmpty ? null : _backspace,
                onLongPress: () => setState(() {
                  _typed = '';
                  _zeros = true;
                }),
                icon: const Icon(Icons.backspace_outlined),
              ),
            ],
          ),
        ),
        Expanded(child: Row(children: [digit('1'), digit('2'), digit('3')])),
        Expanded(child: Row(children: [digit('4'), digit('5'), digit('6')])),
        Expanded(child: Row(children: [digit('7'), digit('8'), digit('9')])),
        Expanded(
          child: Row(
            children: [
              key(const Icon(Icons.monetization_on_outlined), widget.onCoin, color: _pal.textSecondary),
              digit('0'),
              key(const Icon(Icons.casino_outlined), widget.onDice, color: _pal.textSecondary),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              key(
                const Text('− Restar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                () => _apply(1),
                filled: true,
                color: _pal.loss,
              ),
              key(
                const Text('+ Sumar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                () => _apply(-1),
                filled: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Relojes de un jugador: el de su turno (vuelve a 0 en cada turno) y su
/// total de la partida. Tocar: si es su turno, lo pasa al rival; si no,
/// empieza a correr el suyo. Mantener pulsado: pausa.
class _Clocks extends StatelessWidget {
  const _Clocks({required this.match, required this.player, required this.now, required this.onAct});

  final DuelMatch match;
  final int player;
  final DateTime now;
  final void Function(void Function(DuelMatch m)) onAct;

  @override
  Widget build(BuildContext context) {
    final m = match;
    final active = m.active == player;
    // Antes de empezar el duelo: el que empieza toca su reloj.
    final start = m.turn == 0 && !m.clockRunning;
    final fg = active ? _pal.background : _pal.textSecondary;
    final tabular = const [FontFeature.tabularFigures()];
    return Material(
      color: active ? _pal.neon : _pal.surfaceHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: m.matchOver ? null : () => onAct((m) => active ? m.passTurn() : m.startClock(player)),
        onLongPress: active ? () => onAct((m) => m.pauseClock()) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: start
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow, size: 20, color: fg),
                    Text(
                      'Empiezo yo',
                      style: TextStyle(fontWeight: FontWeight.w900, color: fg),
                    ),
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(active ? Icons.timer : Icons.pause, size: 18, color: fg),
                    const SizedBox(width: 4),
                    // Tiempo de este turno (grande) y total de la partida.
                    Text(
                      // Fuera de su turno, a 0 (en pausa durante su turno, el que lleva).
                      formatClock(
                        active || (!m.clockRunning && m.lastActive == player)
                            ? m.turnElapsed(player, now)
                            : Duration.zero,
                      ),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: fg, fontFeatures: tabular),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Total ${formatClock(m.elapsed(player, now))}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg, fontFeatures: tabular),
                    ),
                  ],
                ),
        ),
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
                      }, color: lp ? (delta >= 0 ? _pal.neon : _pal.loss) : _pal.textSecondary),
                      title: Text(
                        lp ? '$who${e.from} → ${e.to}' : '$who${e.text}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: lp ? Text(e.text) : null,
                      trailing: Text(
                        'D${e.game} · ${hm(e.at)}',
                        style: TextStyle(fontSize: 12, color: _pal.textSecondary),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
