import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/features/tournaments/domain/round_import.dart';

void main() {
  const players = [
    ImportCandidate(id: 'a', nickname: 'Ana'),
    ImportCandidate(id: 'l', nickname: 'Luis'),
    ImportCandidate(id: 'p', nickname: 'Pedro'),
    ImportCandidate(id: 'j', nickname: 'José', fullName: 'José Pérez'),
    ImportCandidate(id: 'm', nickname: 'Mariela'),
  ];

  test('lee el texto compartido de una ronda', () {
    final r = parseRoundText(
      '*Liga Garage · Ronda 1*\n\n'
      'Mesa 2: *Ana* 2-1 Luis\n'
      'Mesa 1: jose vs Mariela\n'
      'BYE: Pedro\n\n'
      'Faltan 1 resultado(s).',
      players,
    );
    expect(r.pairs, [('a', 'l'), ('j', 'm'), ('p', null)]);
    expect(r.tables, {'a': 2, 'j': 1});
    expect(r.problems, isEmpty);
  });

  test('avisa de nombres desconocidos, repetidos y mesas repetidas', () {
    final r = parseRoundText(
      '1. Ana vs Carlos\n'
      '2. Luis vs Pedro\n'
      '2. Ana vs Mariela\n'
      'José Pérez vs Luis\n',
      players,
    );
    expect(r.pairs, [('l', 'p'), ('a', 'm')]);
    expect(r.tables, {'l': 2});
    expect(r.problems.first, contains('Carlos'));
    expect(r.problems.any((p) => p.contains('Mesa 2 repetida')), isTrue);
    expect(r.problems.any((p) => p.contains('Luis aparece más de una vez')), isTrue);
  });

  test('BYE en distintas formas y un solo BYE', () {
    final r = parseRoundText('Pedro BYE\nAna (BYE)\nLuis vs Mariela', players);
    expect(r.pairs, [('p', null), ('l', 'm')]);
    expect(r.problems.any((p) => p.contains('Más de un BYE')), isTrue);
  });
}
