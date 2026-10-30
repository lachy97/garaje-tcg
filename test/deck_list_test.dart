import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/features/decklists/domain/card_db.dart';
import 'package:garaje_tcg/features/decklists/domain/deck_list.dart';
import 'package:garaje_tcg/features/decklists/presentation/deck_list_export.dart';

final _db = CardDb(const [
  YgoCard(id: 1, name: 'Blackwing - Gale the Whirlwind', frame: 'effect', altIds: [11]),
  YgoCard(id: 2, name: 'Mystical Space Typhoon', frame: 'spell'),
  YgoCard(id: 3, name: 'Bottomless Trap Hole', frame: 'trap'),
  YgoCard(id: 4, name: 'Black-Winged Dragon', frame: 'synchro'),
  YgoCard(id: 5, name: 'Card of Safe Return', frame: 'spell', limit: 0),
  YgoCard(id: 6, name: 'Brionac, Dragon of the Ice Barrier', frame: 'synchro', limit: 1),
]);

void main() {
  test('lee un .ydk con secciones, comentarios y arte alternativo', () {
    const ydk = '#created by EDOPro\r\n#main\r\n1\r\n11\r\n2\r\n999\r\n'
        '#extra\r\n4\r\n6\r\n6\r\n!side\r\n3\r\n';
    final r = parseYdk(ydk, _db);
    expect(r.cards.main, [1, 1, 2]);
    expect(r.cards.extra, [4, 6, 6]);
    expect(r.cards.side, [3]);
    expect(r.unknown, [999]);
  });

  test('.ydk de ida y vuelta', () {
    final d = DeckCards(main: [1, 2, 2], extra: [4], side: [3]);
    final again = parseYdk(d.toYdk(), _db).cards;
    expect(again.main, [1, 2, 2]);
    expect(again.extra, [4]);
    expect(again.side, [3]);
    expect(DeckCards.parseCodes(DeckCards.joinCodes(d.main)), d.main);
    expect(DeckCards.parseCodes(''), isEmpty);
  });

  test('avisos: tamaño, banlist, copias y Extra Deck', () {
    final d = DeckCards(
      main: [for (var i = 0; i < 39; i++) 2, 5, 4],
      extra: [6, 6, 1],
    );
    final w = validateDeck(d, _db);
    expect(w.any((x) => x.contains('41 cartas') || x.contains('mínimo 40')), isFalse);
    expect(w, contains('Card of Safe Return está prohibida en Edison.'));
    expect(w, contains('Mystical Space Typhoon: 39 copias (máximo 3).'));
    expect(w, contains('Brionac, Dragon of the Ice Barrier: 2 copias, está limitada (1 copia).'));
    expect(w, contains('Black-Winged Dragon es del Extra Deck y está en el Main.'));
    expect(w, contains('Blackwing - Gale the Whirlwind no es del Extra Deck y está en el Extra.'));
    expect(validateDeck(DeckCards(main: [1]), _db).first, 'El Main tiene 1 cartas (mínimo 40).');
  });

  test('agrupar: monstruos, mágicas, trampas y copias', () {
    final d = DeckCards(main: [3, 2, 1, 2, 1, 1]);
    final g = groupedSection(d, DeckSection.main, _db);
    expect(g.map((e) => (e.$1.id, e.$2)), [(1, 3), (2, 2), (3, 1)]);
  });

  test('quitar y mover copias', () {
    final d = DeckCards(main: [1, 1]);
    expect(d.remove(DeckSection.main, 1), isTrue);
    d.add(DeckSection.side, 1);
    expect(d.main, [1]);
    expect(d.side, [1]);
    expect(d.total(1), 2);
    expect(d.remove(DeckSection.extra, 1), isFalse);
  });

  test('fondo que contrasta con la carta principal', () {
    final onLight = contrastBackground(const Color(0xFFF2E6A0)); // amarillo claro
    expect(onLight.computeLuminance(), lessThan(0.1));
    final onDark = contrastBackground(const Color(0xFF1A2A6C)); // azul oscuro
    expect(onDark.computeLuminance(), greaterThan(0.4));
    final hue = HSLColor.fromColor(onDark).hue;
    expect((hue - (HSLColor.fromColor(const Color(0xFF1A2A6C)).hue + 180) % 360).abs(),
        lessThan(2));
    expect(textOn(onLight), Colors.white);
  });
}
