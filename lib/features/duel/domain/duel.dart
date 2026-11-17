/// Calculadora de vida (LP) de una partida de Yu-Gi-Oh! (al mejor de 3),
/// con un solo teléfono en el centro de la mesa. Dart puro (sin Flutter):
/// así se prueba y se guarda en el teléfono como JSON.
///
/// Jugador 0 = la mitad de abajo (en un torneo, yo); 1 = la de arriba
/// (girada, el rival).
library;

/// LP iniciales de cada duelo.
const kStartLp = 8000;

/// Cantidad escrita en el teclado. Se autocompleta con "00" mientras el
/// resultado no pase de 4 cifras: "5" → 500, "18" → 1800. Con 3 cifras o
/// más se toma tal cual: "150" → 150, "1800" → 1800, "050" → 50.
int? typedAmount(String digits) {
  if (digits.isEmpty) return null;
  final n = int.tryParse(digits);
  if (n == null) return null;
  return digits.length <= 2 ? n * 100 : n;
}

/// Lo que se ve al escribir: lo tecleado y el "00" que se añade (en gris).
(String typed, String suffix) typedPreview(String digits) =>
    (digits, digits.isNotEmpty && digits.length <= 2 ? '00' : '');

/// Una línea del registro del duelo.
class DuelLogEntry {
  const DuelLogEntry({
    required this.at,
    required this.game,
    required this.text,
    this.player,
    this.from,
    this.to,
    this.kind = 'lp',
  });

  factory DuelLogEntry.fromJson(Map<String, Object?> j) => DuelLogEntry(
    at: DateTime.fromMillisecondsSinceEpoch((j['at']! as num).toInt()),
    game: (j['g'] as num?)?.toInt() ?? 1,
    text: (j['t'] as String?) ?? '',
    player: (j['p'] as num?)?.toInt(),
    from: (j['f'] as num?)?.toInt(),
    to: (j['to'] as num?)?.toInt(),
    kind: (j['k'] as String?) ?? 'lp',
  );

  Map<String, Object?> toJson() => {
    'at': at.millisecondsSinceEpoch,
    'g': game,
    't': text,
    if (player != null) 'p': player,
    if (from != null) 'f': from,
    if (to != null) 'to': to,
    'k': kind,
  };

  final DateTime at;

  /// Duelo de la partida (1, 2, 3).
  final int game;
  final String text;

  /// Jugador al que afecta (null = los dos / la mesa).
  final int? player;
  final int? from;
  final int? to;

  /// lp | coin | dice | game | turn
  final String kind;
}

/// Una partida (al mejor de 3) con su reloj de ajedrez: solo corre el tiempo
/// del jugador que está jugando su turno.
class DuelMatch {
  DuelMatch({
    required this.names,
    this.tournamentId,
    this.matchId,
    this.iAmP1 = true,
    this.topCut = false,
    List<int>? lp,
    List<int>? games,
    List<DuelLogEntry>? log,
    List<int>? clockMs,
    List<List<int>>? gameClockMs,
    List<int>? gameStartMs,
    this.active,
    this.runningSince,
    this.turn = 0,
    List<DuelSnap>? undo,
    List<DuelSnap>? redo,
  }) : lp = lp ?? [kStartLp, kStartLp],
       games = games ?? [],
       log = log ?? [],
       clockMs = clockMs ?? [0, 0],
       gameClockMs = gameClockMs ?? [],
       gameStartMs = gameStartMs ?? [0, 0],
       _undo = undo ?? [],
       _redo = redo ?? [];

  /// Nombres: [abajo, arriba].
  final List<String> names;

  /// Partida de un torneo (para reportar el resultado al terminar).
  final String? tournamentId;
  final String? matchId;

  /// El jugador de abajo es el jugador 1 de la mesa (los marcadores se
  /// reportan desde él).
  final bool iAmP1;
  final bool topCut;

  final List<int> lp;

  /// Ganador de cada duelo terminado: 0, 1 o -1 (empate).
  final List<int> games;
  final List<DuelLogEntry> log;

  /// Tiempo jugado por cada jugador en toda la partida (sin contar el tramo
  /// que está corriendo ahora).
  final List<int> clockMs;

  /// Tiempo de cada jugador en cada duelo terminado.
  final List<List<int>> gameClockMs;

  /// [clockMs] al empezar el duelo actual (para el tiempo de cada duelo).
  final List<int> gameStartMs;

  /// Jugador cuyo reloj corre (null = parado).
  int? active;
  DateTime? runningSince;

  /// Turno del duelo actual (sube al pasar el turno).
  int turn;

  final List<DuelSnap> _undo;
  final List<DuelSnap> _redo;

  /// Duelo en juego (1, 2, 3).
  int get game => games.length + 1;

  int winsOf(int p) => games.where((g) => g == p).length;
  int get draws => games.where((g) => g == -1).length;

  /// La partida terminó: alguien ganó 2 duelos o ya se jugaron 3.
  bool get matchOver => winsOf(0) >= 2 || winsOf(1) >= 2 || games.length >= 3;

  /// Alguien llegó a 0 en el duelo actual (falta confirmarlo).
  int? get loserAtZero => lp[0] <= 0 ? 0 : (lp[1] <= 0 ? 1 : null);

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  // ───────────── LP ─────────────

  void _snapshot() {
    _undo.add(DuelSnap([...lp], log.length, [...games]));
    if (_undo.length > 200) _undo.removeAt(0);
    _redo.clear();
  }

  void _setLp(int p, int value, String text, DateTime now) {
    final from = lp[p];
    final to = value < 0 ? 0 : value;
    if (to == from) return;
    _snapshot();
    lp[p] = to;
    log.add(DuelLogEntry(at: now, game: game, player: p, from: from, to: to, text: text));
  }

  /// Resta (o suma con [amount] negativo) LP al jugador [p].
  void damage(int p, int amount, {DateTime? now, String? note}) {
    if (amount == 0) return;
    final sign = amount > 0 ? '−' : '+';
    _setLp(p, lp[p] - amount, note ?? '$sign${amount.abs()}', now ?? DateTime.now());
  }

  /// Mitad de los LP (Solemn Judgment, Shrink…). Si es impar, redondea
  /// hacia arriba.
  void halve(int p, {DateTime? now}) => _setLp(p, (lp[p] + 1) ~/ 2, '½', now ?? DateTime.now());

  /// Pone los LP en un valor concreto.
  void setLp(int p, int value, {DateTime? now}) => _setLp(p, value, '= $value', now ?? DateTime.now());

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(DuelSnap([...lp], log.length, [...games], [...log.sublist(_undo.last.logLength)]));
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) return;
    final s = _redo.removeLast();
    _undo.add(DuelSnap([...lp], log.length, [...games]));
    lp
      ..[0] = s.lp[0]
      ..[1] = s.lp[1];
    log.addAll(s.removed ?? const []);
  }

  void _restore(DuelSnap s) {
    lp
      ..[0] = s.lp[0]
      ..[1] = s.lp[1];
    if (log.length > s.logLength) log.removeRange(s.logLength, log.length);
  }

  /// Anota en el registro (moneda, dado…), sin cambiar los LP.
  void note(String text, {String kind = 'note', int? player, DateTime? now}) =>
      log.add(DuelLogEntry(at: now ?? DateTime.now(), game: game, player: player, text: text, kind: kind));

  // ───────────── Reloj de ajedrez ─────────────

  /// Tiempo jugado por [p] en la partida.
  Duration elapsed(int p, DateTime now) => Duration(
    milliseconds: clockMs[p] + (active == p && runningSince != null ? now.difference(runningSince!).inMilliseconds : 0),
  );

  /// Tiempo de [p] en el duelo actual.
  Duration gameElapsed(int p, DateTime now) => elapsed(p, now) - Duration(milliseconds: gameStartMs[p]);

  void _stopClock(DateTime now) {
    final a = active;
    if (a != null && runningSince != null) {
      clockMs[a] += now.difference(runningSince!).inMilliseconds;
    }
    active = null;
    runningSince = null;
  }

  /// Empieza a correr el tiempo de [p] (y para el del otro).
  void startClock(int p, {DateTime? now}) {
    final t = now ?? DateTime.now();
    if (active == p) return;
    final first = turn == 0;
    _stopClock(t);
    active = p;
    runningSince = t;
    if (first) {
      turn = 1;
      note('Duelo $game: empieza ${names[p]}', kind: 'turn', player: p, now: t);
    }
  }

  /// Pasa el turno: para el reloj del que jugaba y arranca el del rival.
  void passTurn({DateTime? now}) {
    final a = active;
    if (a == null) return;
    final t = now ?? DateTime.now();
    _stopClock(t);
    active = 1 - a;
    runningSince = t;
    turn++;
  }

  /// Para el reloj (pausa: llamada al juez, entre duelos…).
  void pauseClock({DateTime? now}) => _stopClock(now ?? DateTime.now());

  bool get clockRunning => active != null;

  // ───────────── Duelos y partida ─────────────

  /// Cierra el duelo actual: [winner] 0, 1 o -1 (empate). Para el reloj y
  /// guarda el tiempo de cada uno en ese duelo.
  void endGame(int winner, {DateTime? now}) {
    final t = now ?? DateTime.now();
    _stopClock(t);
    gameClockMs.add([clockMs[0] - gameStartMs[0], clockMs[1] - gameStartMs[1]]);
    final g = game;
    games.add(winner);
    log.add(
      DuelLogEntry(
        at: t,
        game: g,
        player: winner < 0 ? null : winner,
        kind: 'game',
        text: winner < 0 ? 'Duelo $g: empate' : 'Duelo $g: gana ${names[winner]}',
      ),
    );
    _undo.clear();
    _redo.clear();
  }

  /// Siguiente duelo: LP a 8000 y turno 0 (el reloj espera a que alguien
  /// empiece).
  void nextGame() {
    if (matchOver) return;
    lp
      ..[0] = kStartLp
      ..[1] = kStartLp;
    gameStartMs
      ..[0] = clockMs[0]
      ..[1] = clockMs[1];
    turn = 0;
    _undo.clear();
    _redo.clear();
  }

  /// Vuelve a empezar el duelo actual (LP a 8000), sin tocar el reloj.
  void resetGame({DateTime? now}) {
    _snapshot();
    lp
      ..[0] = kStartLp
      ..[1] = kStartLp;
    log.add(DuelLogEntry(at: now ?? DateTime.now(), game: game, kind: 'game', text: 'LP a $kStartLp'));
  }

  /// Marcador de la partida desde el jugador de abajo: (ganados, empates,
  /// perdidos).
  (int, int, int) get score => (winsOf(0), draws, winsOf(1));

  /// Marcador para reportar, visto desde el jugador 1 de la mesa: (p1,
  /// empates, p2). null si no es un marcador que se pueda reportar.
  (int, int, int)? reportScore() {
    final (w, d, l) = score;
    const allowed = {(2, 0, 0), (2, 0, 1), (0, 0, 2), (1, 0, 2), (1, 1, 1)};
    final s = iAmP1 ? (w, d, l) : (l, d, w);
    if (!allowed.contains(s)) return null;
    if (topCut && d > 0) return null;
    return s;
  }

  // ───────────── JSON ─────────────

  Map<String, Object?> toJson() => {
    'v': 1,
    'names': names,
    'tid': tournamentId,
    'mid': matchId,
    'p1': iAmP1,
    'top': topCut,
    'lp': lp,
    'games': games,
    'log': [for (final e in log) e.toJson()],
    'clock': clockMs,
    'gclock': gameClockMs,
    'gstart': gameStartMs,
    'active': active,
    'since': runningSince?.millisecondsSinceEpoch,
    'turn': turn,
    'undo': [for (final s in _undo) s.toJson()],
    'redo': [for (final s in _redo) s.toJson()],
  };

  factory DuelMatch.fromJson(Map<String, Object?> j) {
    List<int> ints(Object? v, List<int> d) => v is List ? [for (final x in v) (x as num).toInt()] : d;
    return DuelMatch(
      names: [
        for (final n in (j['names'] as List?) ?? const ['Jugador 1', 'Jugador 2']) '$n',
      ],
      tournamentId: j['tid'] as String?,
      matchId: j['mid'] as String?,
      iAmP1: j['p1'] != false,
      topCut: j['top'] == true,
      lp: ints(j['lp'], [kStartLp, kStartLp]),
      games: ints(j['games'], []),
      log: [for (final e in (j['log'] as List?) ?? const []) DuelLogEntry.fromJson((e as Map).cast<String, Object?>())],
      clockMs: ints(j['clock'], [0, 0]),
      gameClockMs: [
        for (final g in (j['gclock'] as List?) ?? const []) ints(g, [0, 0]),
      ],
      gameStartMs: ints(j['gstart'], [0, 0]),
      active: (j['active'] as num?)?.toInt(),
      runningSince: j['since'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['since']! as num).toInt()),
      turn: (j['turn'] as num?)?.toInt() ?? 0,
      undo: [for (final s in (j['undo'] as List?) ?? const []) DuelSnap.fromJson((s as Map).cast<String, Object?>())],
      redo: [for (final s in (j['redo'] as List?) ?? const []) DuelSnap.fromJson((s as Map).cast<String, Object?>())],
    );
  }

  DuelMatch copy() => DuelMatch.fromJson(toJson());
}

/// Estado guardado para deshacer: LP, largo del registro y duelos (uso interno).
class DuelSnap {
  DuelSnap(this.lp, this.logLength, this.games, [this.removed]);

  factory DuelSnap.fromJson(Map<String, Object?> j) => DuelSnap(
    [for (final x in j['lp']! as List) (x as num).toInt()],
    (j['n']! as num).toInt(),
    [for (final x in (j['g'] as List?) ?? const []) (x as num).toInt()],
    j['r'] == null
        ? null
        : [for (final e in j['r']! as List) DuelLogEntry.fromJson((e as Map).cast<String, Object?>())],
  );

  final List<int> lp;
  final int logLength;
  final List<int> games;

  /// Rehacer: líneas del registro que quitó el deshacer.
  final List<DuelLogEntry>? removed;

  Map<String, Object?> toJson() => {
    'lp': lp,
    'n': logLength,
    'g': games,
    if (removed != null) 'r': [for (final e in removed!) e.toJson()],
  };
}

/// "12:05" o "1:02:05".
String formatClock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
}
