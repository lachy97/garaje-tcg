import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'players_dao.g.dart';

@DriftAccessor(tables: [Players])
class PlayersDao extends DatabaseAccessor<AppDatabase> with _$PlayersDaoMixin {
  PlayersDao(super.attachedDatabase);

  /// Jugadores activos ordenados por nickname. Filtra por [query] si se indica.
  Stream<List<Player>> watchAll({String query = ''}) {
    final q = select(players)..where((p) => p.deletedAt.isNull());
    final term = query.trim();
    if (term.isNotEmpty) {
      q.where((p) => p.nickname.like('%$term%') | p.fullName.like('%$term%'));
    }
    q.orderBy([(p) => OrderingTerm.asc(p.nickname.lower())]);
    return q.watch();
  }

  Future<Player?> getById(String id) =>
      (select(players)..where((p) => p.id.equals(id))).getSingleOrNull();

  Stream<Player?> watchById(String id) =>
      (select(players)..where((p) => p.id.equals(id))).watchSingleOrNull();

  Future<Player> create({
    required String nickname,
    String? fullName,
    String? photoPath,
    String? notes,
    String? konamiId,
    String? phone,
  }) {
    return into(players).insertReturning(PlayersCompanion.insert(
      nickname: nickname.trim(),
      fullName: Value(_blankToNull(fullName)),
      photoPath: Value(photoPath),
      notes: Value(_blankToNull(notes)),
      konamiId: Value(_blankToNull(konamiId)),
      phone: Value(_blankToNull(phone)),
    ));
  }

  Future<void> edit(
    String id, {
    String? nickname,
    Value<String?> fullName = const Value.absent(),
    Value<String?> photoPath = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<String?> konamiId = const Value.absent(),
    Value<String?> phone = const Value.absent(),
  }) {
    return (update(players)..where((p) => p.id.equals(id))).write(
      PlayersCompanion(
        nickname: nickname == null ? const Value.absent() : Value(nickname.trim()),
        fullName: fullName,
        photoPath: photoPath,
        notes: notes,
        konamiId: konamiId,
        phone: phone,
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Borrado lógico: el historial de matches sigue intacto.
  Future<void> softDelete(String id) {
    final now = DateTime.now();
    return (update(players)..where((p) => p.id.equals(id))).write(
      PlayersCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  String? _blankToNull(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();
}
