/// Textos para compartir rondas y clasificación por WhatsApp. Dart puro.
///
/// WhatsApp pone en negrita lo que va entre asteriscos: `*Ana*`.
library;

/// Un match de la ronda, ya con nombres.
class ShareMatchLine {
  const ShareMatchLine({
    this.table,
    required this.player1,
    this.player2,
    this.score,
    this.winner = 0,
    this.isThirdPlace = false,
  });

  final int? table;
  final String player1;

  /// null = BYE.
  final String? player2;

  /// Marcador visto desde el jugador 1 ("2-1", "1-2", "Empate 1-1-1", "ID",
  /// "Doble derrota"). null = pendiente.
  final String? score;

  /// 0 = ninguno (pendiente, empate o doble derrota), 1 o 2.
  final int winner;
  final bool isThirdPlace;
}

/// Una fila de la clasificación.
class ShareStandingLine {
  const ShareStandingLine({
    required this.rank,
    required this.name,
    required this.points,
    required this.wins,
    required this.losses,
    required this.draws,
    this.dropped = false,
  });

  final int rank;
  final String name;
  final int points;
  final int wins;
  final int losses;
  final int draws;
  final bool dropped;
}

String _bold(String s) => '*$s*';

String roundShareText({
  required String tournament,
  required String roundTitle,
  required List<ShareMatchLine> lines,
  bool isTopCut = false,
}) {
  final b = StringBuffer()
    ..writeln(_bold('$tournament · $roundTitle'))
    ..writeln();
  for (final l in lines) {
    if (l.player2 == null) {
      b.writeln('BYE: ${l.player1}');
      continue;
    }
    final where = l.isThirdPlace
        ? '3er puesto'
        : l.table == null
            ? null
            : isTopCut
                ? 'Match ${l.table}'
                : 'Mesa ${l.table}';
    final p1 = l.winner == 1 ? _bold(l.player1) : l.player1;
    final p2 = l.winner == 2 ? _bold(l.player2!) : l.player2!;
    final middle = l.score ?? 'vs';
    b.writeln('${where == null ? '' : '$where: '}$p1 $middle $p2');
  }
  final pending = lines.where((l) => l.player2 != null && l.score == null).length;
  final playable = lines.where((l) => l.player2 != null).length;
  if (pending > 0 && pending < playable) {
    b
      ..writeln()
      ..writeln('Faltan $pending resultado(s).');
  }
  return b.toString().trimRight();
}

/// [cut] = jugadores activos que pasan al Top (0 = sin Top). La línea de corte
/// se pone después del último activo que entra.
String standingsShareText({
  required String tournament,
  required String subtitle,
  required List<ShareStandingLine> rows,
  int cut = 0,
}) {
  final b = StringBuffer()
    ..writeln(_bold('$tournament · $subtitle'))
    ..writeln();
  var activeSeen = 0;
  for (final r in rows) {
    final name = r.dropped ? '${r.name} (drop)' : r.name;
    b.writeln('${r.rank}. $name · ${r.points} pts (${r.wins}-${r.losses}-${r.draws})');
    if (!r.dropped) {
      activeSeen++;
      if (cut > 0 && activeSeen == cut) b.writeln('────── Corte Top $cut ──────');
    }
  }
  return b.toString().trimRight();
}
