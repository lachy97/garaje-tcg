import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/duel_visuals.dart';

/// Cuánto dura el lanzamiento (moneda y dado).
const kRollDuration = Duration(seconds: 2);

// ───────────────────────────── Moneda ─────────────────────────────

/// Moneda lanzada al aire: sube, gira sobre sí misma cada vez más despacio
/// y cae mostrando [heads] (cara) o cruz. Dura 2 s y luego llama a [onDone].
class CoinFlip extends StatefulWidget {
  const CoinFlip({super.key, required this.heads, required this.accent, this.onDone, this.size = 150});

  final bool heads;
  final Color accent;
  final VoidCallback? onDone;
  final double size;

  @override
  State<CoinFlip> createState() => _CoinFlipState();
}

class _CoinFlipState extends State<CoinFlip> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: kRollDuration);

  /// Medias vueltas (cada una enseña la otra cara): par = termina en cara.
  late final int _halfTurns = () {
    final base = 14 + Random().nextInt(6) * 2; // 7–12 vueltas completas
    return widget.heads ? base : base + 1;
  }();

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(() {
      HapticFeedback.mediumImpact();
      widget.onDone?.call();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 1.6,
      height: s * 2.2,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = _c.value;
          // Giro: rápido al principio y frenando hasta parar en la cara.
          final angle = Curves.easeOutCubic.transform(t) * _halfTurns * pi;
          // Vuelo: sube y cae (parábola) en el 80 % del tiempo y da un
          // pequeño rebote al tocar la mesa.
          double lift;
          if (t < 0.8) {
            final u = t / 0.8;
            lift = 4 * u * (1 - u) * s * 0.75;
          } else {
            final u = (t - 0.8) / 0.2;
            lift = sin(u * pi) * s * 0.08 * (1 - u);
          }
          // Se ve más grande arriba (más cerca).
          final scale = 1 + 0.25 * (lift / (s * 0.75));
          final front = cos(angle) >= 0;
          final face = front
              ? _CoinFace(heads: true, accent: widget.accent, size: s)
              // La cara de atrás se gira para que no se lea al revés.
              : Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.rotationX(pi),
                  child: _CoinFace(heads: false, accent: widget.accent, size: s),
                );
          // Sombra en la mesa: más pequeña y suave cuanto más alta está.
          final shadow = 1 - (lift / (s * 0.9)).clamp(0.0, 0.8);
          return Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                bottom: s * 0.08,
                child: Container(
                  width: s * 0.9 * shadow,
                  height: s * 0.14 * shadow,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(s),
                    color: Colors.black.withValues(alpha: 0.45 * shadow),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4 * shadow), blurRadius: 12)],
                  ),
                ),
              ),
              Positioned(
                bottom: s * 0.15 + lift,
                child: Transform.scale(
                  scale: scale,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0018)
                      ..rotateX(angle),
                    child: face,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Una cara de la moneda: dorada, con borde acuñado.
class _CoinFace extends StatelessWidget {
  const _CoinFace({required this.heads, required this.accent, required this.size});

  final bool heads;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFE9B949);
    const goldLight = Color(0xFFFFE9A6);
    const goldDark = Color(0xFF9A6B12);
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(-0.35, -0.4),
          radius: 0.95,
          colors: [goldLight, gold, goldDark],
          stops: [0.0, 0.55, 1.0],
        ),
        boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 3))],
      ),
      padding: EdgeInsets.all(size * 0.07),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: goldDark.withValues(alpha: 0.8), width: size * 0.025),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(heads ? Icons.star_rounded : Icons.close_rounded, size: size * 0.42, color: goldDark),
            Text(
              heads ? 'CARA' : 'CRUZ',
              style: TextStyle(fontSize: size * 0.13, fontWeight: FontWeight.w900, letterSpacing: 2, color: goldDark),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── Dado ─────────────────────────────

/// Dado en 3D que rueda y rebota durante 2 s, frenando hasta quedar con
/// [value] arriba (de frente). Luego llama a [onDone].
class DiceRoll extends StatefulWidget {
  const DiceRoll({super.key, required this.value, this.onDone, this.size = 110});

  final int value;
  final VoidCallback? onDone;
  final double size;

  @override
  State<DiceRoll> createState() => _DiceRollState();
}

class _DiceRollState extends State<DiceRoll> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: kRollDuration);
  final _rnd = Random();

  /// Vueltas extra sobre cada eje (al azar), que se van frenando.
  late final double _spinX = (3 + _rnd.nextInt(3)) * 2 * pi * (_rnd.nextBool() ? 1 : -1);
  late final double _spinY = (3 + _rnd.nextInt(3)) * 2 * pi * (_rnd.nextBool() ? 1 : -1);
  late final double _driftX = (_rnd.nextDouble() - 0.5) * 80;

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(() {
      HapticFeedback.mediumImpact();
      widget.onDone?.call();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final (restX, restY) = diceRestAngles(widget.value);
    return SizedBox(
      width: s * 2.4,
      height: s * 2.4,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = _c.value;
          final e = Curves.easeOutCubic.transform(t);
          final ax = restX + (1 - e) * _spinX;
          final ay = restY + (1 - e) * _spinY;
          // Rebotes sobre la mesa, cada vez más bajos.
          final hop = (sin(t * 3 * pi)).abs() * (1 - t) * (1 - t) * s * 0.9;
          final dx = _driftX * (1 - e);
          final faces = [
            for (final f in DiceFace.values)
              if (diceFaceZ(f, ax, ay) < 0) (f, diceFaceZ(f, ax, ay)),
          ]..sort((a, b) => b.$2.compareTo(a.$2)); // las más de lado primero
          final shadow = 1 - (hop / (s * 0.9)).clamp(0.0, 0.7);
          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                bottom: s * 0.25,
                left: s * 1.2 - s * 0.5 * shadow + dx,
                child: Container(
                  width: s * shadow,
                  height: s * 0.18 * shadow,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(s),
                    color: Colors.black.withValues(alpha: 0.45 * shadow),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4 * shadow), blurRadius: 14)],
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(dx, -hop),
                child: SizedBox(
                  width: s,
                  height: s,
                  child: Stack(
                    children: [
                      for (final (f, z) in faces)
                        Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.0022)
                            ..rotateX(ax)
                            ..rotateY(ay)
                            ..rotateX(f.rx)
                            ..rotateY(f.ry)
                            ..translateByDouble(0.0, 0.0, -s / 2, 1),
                          // Las caras de lado, más oscuras (luz de frente).
                          child: _DiceFaceView(value: f.value, size: s, light: (-z).clamp(0.0, 1.0)),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DiceFaceView extends StatelessWidget {
  const _DiceFaceView({required this.value, required this.size, required this.light});

  final int value;
  final double size;

  /// 1 = de frente (con toda la luz), 0 = de lado.
  final double light;

  @override
  Widget build(BuildContext context) {
    final base = Color.lerp(const Color(0xFFB9B4A8), const Color(0xFFFFFDF6), light)!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, Color.lerp(base, const Color(0xFF8C877C), 0.35)!],
        ),
        border: Border.all(color: const Color(0x33000000), width: 1),
      ),
      child: CustomPaint(painter: _PipsPainter(value)),
    );
  }
}

/// Puntos de una cara del dado (el 1 en rojo, como los dados clásicos).
class _PipsPainter extends CustomPainter {
  _PipsPainter(this.value);

  final int value;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final r = w * (value == 1 ? 0.12 : 0.085);
    final paint = Paint()..color = value == 1 ? const Color(0xFFC62828) : const Color(0xFF1B1B1B);
    const a = 0.25, m = 0.5, b = 0.75;
    final pts = switch (value) {
      1 => [(m, m)],
      2 => [(a, a), (b, b)],
      3 => [(a, a), (m, m), (b, b)],
      4 => [(a, a), (b, a), (a, b), (b, b)],
      5 => [(a, a), (b, a), (m, m), (a, b), (b, b)],
      _ => [(a, a), (b, a), (a, m), (b, m), (a, b), (b, b)],
    };
    for (final (x, y) in pts) {
      // Hundidos: un poco de sombra arriba a la izquierda.
      canvas.drawCircle(Offset(x * w + 1, y * w + 1), r, Paint()..color = const Color(0x33FFFFFF));
      canvas.drawCircle(Offset(x * w, y * w), r, paint);
    }
  }

  @override
  bool shouldRepaint(_PipsPainter old) => old.value != value;
}
