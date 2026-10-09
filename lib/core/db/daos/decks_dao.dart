import 'package:drift/drift.dart';

import '../../../features/decks/domain/deck_catalog.dart';
import '../app_database.dart';
import '../tables.dart';

part 'decks_dao.g.dart';

/// "  Snake-Eye   Fire King " → nombre visible "Snake-Eye Fire King",
/// normalizado "snake-eye fire king".
String cleanDeckName(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');
String normalizeDeckName(String raw) => cleanDeckName(raw).toLowerCase();

@DriftAccessor(tables: [Decks])
class DecksDao extends DatabaseAccessor<AppDatabase> with _$DecksDaoMixin {
  DecksDao(super.attachedDatabase);

  Stream<List<Deck>> watchAll({String game = kDefaultGame}) {
    return (select(decks)
          ..where((d) => d.deletedAt.isNull() & d.game.equals(game))
          ..orderBy([(d) => OrderingTerm.asc(d.normalizedName)]))
        .watch();
  }

  Future<Deck?> getById(String id) =>
      (select(decks)..where((d) => d.id.equals(id))).getSingleOrNull();

  /// Devuelve el mazo con ese nombre (ignorando mayúsculas y espacios) o lo crea.
  /// Si estaba borrado lógicamente, lo restaura.
  Future<Deck> findOrCreate(String rawName, {String game = kDefaultGame, String? imagePath}) {
    final name = cleanDeckName(rawName);
    if (name.isEmpty) {
      throw ArgumentError.value(rawName, 'rawName', 'El nombre del mazo está vacío');
    }
    final norm = name.toLowerCase();
    return transaction(() async {
      final existing = await (select(decks)
            ..where((d) => d.game.equals(game) & d.normalizedName.equals(norm)))
          .getSingleOrNull();
      if (existing != null) {
        if (existing.deletedAt == null) return existing;
        final restored = existing.copyWith(
          deletedAt: const Value(null),
          updatedAt: DateTime.now(),
        );
        await update(decks).replace(restored);
        return restored;
      }
      return into(decks).insertReturning(DecksCompanion.insert(
        game: Value(game),
        name: name,
        normalizedName: norm,
        imagePath: Value(imagePath ?? kDeckCatalogByName[norm]?.asset),
      ));
    });
  }

  /// Carga los mazos del catálogo de Edison Format que falten y pone su imagen
  /// a los que ya existían con ese nombre. Un mazo del catálogo que el usuario
  /// borró o fusionó no se vuelve a crear.
  Future<void> seedCatalog({String game = kDefaultGame}) async {
    final existing = await (select(decks)..where((d) => d.game.equals(game))).get();
    final byNorm = {for (final d in existing) d.normalizedName: d};
    final now = DateTime.now();
    await batch((b) {
      for (final e in kDeckCatalog) {
        final norm = normalizeDeckName(e.name);
        final d = byNorm[norm];
        if (d == null) {
          b.insert(decks, DecksCompanion.insert(
            game: Value(game),
            name: e.name,
            normalizedName: norm,
            imagePath: Value(e.asset),
          ));
        } else if (d.imagePath == null) {
          b.update(decks, DecksCompanion(imagePath: Value(e.asset), updatedAt: Value(now)),
              where: (t) => t.id.equals(d.id));
        }
      }
    });
  }

  /// Cambia (o quita, con null) la imagen de un mazo.
  Future<void> setImage(String id, String? path) {
    return (update(decks)..where((d) => d.id.equals(id))).write(DecksCompanion(
      imagePath: Value(path),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Renombra un mazo. Lanza [StateError] si ya existe otro con ese nombre
  /// (en ese caso usar [merge]).
  Future<void> rename(String id, String newName) async {
    final name = cleanDeckName(newName);
    final norm = name.toLowerCase();
    final current = await getById(id);
    if (current == null) return;
    final clash = await (select(decks)
          ..where((d) =>
              d.game.equals(current.game) &
              d.normalizedName.equals(norm) &
              d.id.equals(id).not()))
        .getSingleOrNull();
    if (clash != null) {
      throw StateError('Ya existe un mazo llamado "${clash.name}"');
    }
    await (update(decks)..where((d) => d.id.equals(id))).write(DecksCompanion(
      name: Value(name),
      normalizedName: Value(norm),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Fusiona [fromId] dentro de [intoId] (corrige mazos duplicados o mal escritos):
  /// reasigna matches e inscripciones y borra lógicamente el origen.
  Future<void> merge({required String fromId, required String intoId}) {
    final db = attachedDatabase;
    final now = DateTime.now();
    return transaction(() async {
      await (update(db.matches)..where((m) => m.deck1Id.equals(fromId)))
          .write(MatchesCompanion(deck1Id: Value(intoId), updatedAt: Value(now)));
      await (update(db.matches)..where((m) => m.deck2Id.equals(fromId)))
          .write(MatchesCompanion(deck2Id: Value(intoId), updatedAt: Value(now)));
      await (update(db.tournamentPlayers)..where((t) => t.deckId.equals(fromId)))
          .write(TournamentPlayersCompanion(
              deckId: Value(intoId), updatedAt: Value(now)));
      await (update(decks)..where((d) => d.id.equals(fromId)))
          .write(DecksCompanion(deletedAt: Value(now), updatedAt: Value(now)));
    });
  }
}
