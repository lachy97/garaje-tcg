import '../../../core/db/enums.dart';

/// Datos mínimos de una inscripción para el resumen (Dart puro).
class ReportEntry {
  const ReportEntry({
    required this.playerId,
    required this.name,
    this.deck,
    this.position,
    this.lateRounds = 0,
    this.dropped = false,
  });

  final String playerId;
  final String name;
  final String? deck;
  final int? position;
  final int lateRounds;
  final bool dropped;
}

/// Datos mínimos de un match para el resumen.
class ReportMatch {
  const ReportMatch({
    required this.player1Id,
    this.player2Id,
    required this.result,
    this.isBye = false,
  });

  final String player1Id;
  final String? player2Id;
  final MatchResult result;
  final bool isBye;
}

/// Una fila de "Participantes": puesto, jugador, récord de TODO el torneo
/// (Swiss y Top Cut) y mazo.
class ParticipantLine {
  const ParticipantLine({
    required this.playerId,
    required this.position,
    required this.name,
    required this.deck,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.madeTop,
    required this.dropped,
  });

  final String playerId;
  final int? position;
  final String name;
  final String? deck;
  final int wins;
  final int losses;
  final int draws;
  final bool madeTop;
  final bool dropped;

  int get played => wins + losses + draws;

  /// Victorias ÷ partidas (0 sin partidas).
  double get winRate => played == 0 ? 0 : wins / played;

  String get record => draws == 0 ? '$wins-$losses' : '$wins-$losses-$draws';
}

/// Cuántos jugadores usaron un mazo.
class DeckShare {
  const DeckShare(this.name, this.players, this.total);

  /// Nombre del mazo; null = sin mazo asignado.
  final String? name;
  final int players;
  final int total;

  double get fraction => total == 0 ? 0 : players / total;
}

/// Resumen de un torneo: participantes y metagame. Dart puro.
class TournamentReport {
  const TournamentReport({required this.participants, required this.metagame});

  /// Por puesto final (los que no tienen puesto, al final por nombre).
  final List<ParticipantLine> participants;

  /// Mazos de más a menos jugadores (a igualdad, alfabético; "sin mazo" al final).
  final List<DeckShare> metagame;

  int get players => participants.length;

  /// Mazos distintos (sin contar "sin mazo").
  int get deckCount => metagame.where((d) => d.name != null).length;

  /// Victorias, derrotas y empates de cada jugador:
  /// - BYE = victoria. Doble derrota = derrota para los dos.
  /// - Cada ronda perdida por inscribirse tarde = derrota.
  /// - Los matches sin resultado no cuentan.
  factory TournamentReport.build({
    required List<ReportEntry> entries,
    required List<ReportMatch> matches,
    required int topCutSize,
  }) {
    final w = <String, int>{}, l = <String, int>{}, d = <String, int>{};
    void add(Map<String, int> m, String? id) {
      if (id != null) m[id] = (m[id] ?? 0) + 1;
    }

    for (final m in matches) {
      if (m.isBye || m.player2Id == null) {
        add(w, m.player1Id);
        continue;
      }
      switch (m.result) {
        case MatchResult.p1Win:
          add(w, m.player1Id);
          add(l, m.player2Id);
        case MatchResult.p2Win:
          add(w, m.player2Id);
          add(l, m.player1Id);
        case MatchResult.draw:
          add(d, m.player1Id);
          add(d, m.player2Id);
        case MatchResult.doubleLoss:
          add(l, m.player1Id);
          add(l, m.player2Id);
        case MatchResult.pending:
          break;
      }
    }

    final lines = [
      for (final e in entries)
        ParticipantLine(
          playerId: e.playerId,
          position: e.position,
          name: e.name,
          deck: e.deck,
          wins: w[e.playerId] ?? 0,
          losses: (l[e.playerId] ?? 0) + e.lateRounds,
          draws: d[e.playerId] ?? 0,
          madeTop: topCutSize > 0 && e.position != null && e.position! <= topCutSize,
          dropped: e.dropped,
        ),
    ]..sort((a, b) {
        final pa = a.position, pb = b.position;
        if (pa != null && pb != null && pa != pb) return pa.compareTo(pb);
        if ((pa == null) != (pb == null)) return pa == null ? 1 : -1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    final counts = <String?, int>{};
    for (final e in entries) {
      final key = (e.deck == null || e.deck!.trim().isEmpty) ? null : e.deck;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final total = entries.length;
    final meta = [
      for (final MapEntry(:key, :value) in counts.entries) DeckShare(key, value, total),
    ]..sort((a, b) {
        if ((a.name == null) != (b.name == null)) return a.name == null ? 1 : -1;
        final c = b.players.compareTo(a.players);
        return c != 0 ? c : (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase());
      });
    return TournamentReport(participants: lines, metagame: meta);
  }
}

/// Porcentaje para mostrar: entero desde el 10 %, con un decimal por debajo
/// ("15 %", "4,5 %"), como en los gráficos de metagame.
String sharePct(double fraction) {
  final p = (fraction * 1000).round() / 10; // un decimal
  if (p >= 10 || p == p.roundToDouble()) return '${p.round()} %';
  return '${p.toStringAsFixed(1).replaceAll('.', ',')} %';
}
