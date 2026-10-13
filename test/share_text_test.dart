import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/features/tournaments/domain/share_text.dart';

void main() {
  test('Texto de la ronda: ganadores en negrita, pendientes con vs y BYE', () {
    final text = roundShareText(
      tournament: 'Torneo #3',
      roundTitle: 'Ronda 2',
      lines: const [
        ShareMatchLine(table: 1, player1: 'Ana', player2: 'Beto', score: '2-1', winner: 1),
        ShareMatchLine(table: 2, player1: 'Caro', player2: 'Dani'),
        ShareMatchLine(table: 3, player1: 'Eli', player2: 'Fede', score: 'ID'),
        ShareMatchLine(player1: 'Gus'),
      ],
    );
    expect(text, startsWith('*Torneo #3 · Ronda 2*'));
    expect(text, contains('Mesa 1: *Ana* 2-1 Beto'));
    expect(text, contains('Mesa 2: Caro vs Dani'));
    expect(text, contains('Mesa 3: Eli ID Fede'));
    expect(text, contains('BYE: Gus'));
    expect(text, contains('Faltan 1 resultado(s).'));
  });

  test('Ronda sin resultados no muestra el aviso de pendientes', () {
    final text = roundShareText(
      tournament: 'T',
      roundTitle: 'Final',
      isTopCut: true,
      lines: const [ShareMatchLine(table: 1, player1: 'A', player2: 'B')],
    );
    expect(text, contains('Match 1: A vs B'));
    expect(text, isNot(contains('Faltan')));
  });

  test('Clasificación con línea de corte que ignora los drops', () {
    final text = standingsShareText(
      tournament: 'T',
      subtitle: 'Clasificación · ronda 3',
      cut: 2,
      rows: const [
        ShareStandingLine(rank: 1, name: 'Ana', points: 9, wins: 3, losses: 0, draws: 0),
        ShareStandingLine(
            rank: 2, name: 'Beto', points: 6, wins: 2, losses: 1, draws: 0, dropped: true),
        ShareStandingLine(rank: 3, name: 'Caro', points: 6, wins: 2, losses: 1, draws: 0),
        ShareStandingLine(rank: 4, name: 'Dani', points: 3, wins: 1, losses: 2, draws: 0),
      ],
    );
    final lines = text.split('\n');
    expect(lines, contains('2. Beto (drop) · 6 pts (2-1-0)'));
    final cutAt = lines.indexWhere((l) => l.contains('Corte Top 2'));
    expect(lines[cutAt - 1], startsWith('3. Caro'));
  });
}
