import 'package:drift/drift.dart';

import '../utils/ids.dart';
import 'enums.dart';

/// Columnas comunes a todas las tablas. Preparan una futura sincronización:
/// - `id` UUID v7 generado en el dispositivo (sin colisiones entre teléfonos)
/// - `updatedAt` para resolver conflictos ("gana el más reciente")
/// - `deletedAt` borrado lógico (un borrado también debe poder sincronizarse)
/// Cada tabla declara `primaryKey => {id}` explícitamente (más fiable para drift_dev).
mixin SyncColumns on Table {
  TextColumn get id => text().clientDefault(newId)();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

// ───────────────────────────── Catálogo ─────────────────────────────

@DataClassName('Player')
class Players extends Table with SyncColumns {
  @override
  Set<Column<Object>> get primaryKey => {id};

  TextColumn get nickname => text().withLength(min: 1, max: 40)();
  TextColumn get fullName => text().nullable()();
  TextColumn get photoPath => text().nullable()();
  TextColumn get notes => text().nullable()();

  /// v3: datos personales del perfil.
  TextColumn get konamiId => text().nullable()(); // Konami / COSSY ID
  TextColumn get phone => text().nullable()();
}

/// El mazo es una entidad propia: sus estadísticas se calculan a partir de
/// los matches donde aparece, sin importar quién lo jugó.
@DataClassName('Deck')
class Decks extends Table with SyncColumns {
  @override
  Set<Column<Object>> get primaryKey => {id};

  TextColumn get game => text().withDefault(const Constant(kDefaultGame))();
  TextColumn get name => text().withLength(min: 1, max: 60)();

  /// Minúsculas + espacios colapsados. Evita duplicados tipo "Snake-Eye" / "snake-eye ".
  TextColumn get normalizedName => text()();
  TextColumn get archetype => text().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {game, normalizedName},
      ];
}

// ───────────────────────────── Temporadas ─────────────────────────────

@DataClassName('Season')
class Seasons extends Table with SyncColumns {
  @override
  Set<Column<Object>> get primaryKey => {id};

  TextColumn get game => text().withDefault(const Constant(kDefaultGame))();
  IntColumn get year => integer()();
  IntColumn get quarter => integer().check(quarter.isBetweenValues(1, 4))();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  TextColumn get status =>
      textEnum<SeasonStatus>().withDefault(const Constant('active'))();
  DateTimeColumn get closedAt => dateTime().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {game, year, quarter},
      ];
}

/// Escala de puntos de ranking por tamaño de Top Cut (editable en Ajustes).
/// Ej: topCutSize=16, positionFrom=5, positionTo=8, points=200.
/// Posiciones sin tramo => 0 puntos (los que no entran al Top no puntúan).
@DataClassName('PointsScaleEntry')
class PointsScaleEntries extends Table with SyncColumns {
  @override
  Set<Column<Object>> get primaryKey => {id};

  IntColumn get topCutSize => integer()();
  IntColumn get positionFrom => integer()();
  IntColumn get positionTo => integer()();
  IntColumn get points => integer()();
}

// ───────────────────────────── Torneos ─────────────────────────────

@DataClassName('Tournament')
class Tournaments extends Table with SyncColumns {
  @override
  Set<Column<Object>> get primaryKey => {id};

  TextColumn get seasonId => text().references(Seasons, #id)();
  TextColumn get game => text().withDefault(const Constant(kDefaultGame))();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  DateTimeColumn get date => dateTime()();
  TextColumn get status =>
      textEnum<TournamentStatus>().withDefault(const Constant('draft'))();
  IntColumn get swissRounds => integer()();

  /// Número de la última ronda creada (Swiss + Top Cut, correlativo). 0 = sin empezar.
  IntColumn get currentRound => integer().withDefault(const Constant(0))();

  /// 0 = sin Top Cut, o 4 / 8 / 16 / 32.
  IntColumn get topCutSize => integer().withDefault(const Constant(0))();
  BoolColumn get hasThirdPlaceMatch =>
      boolean().withDefault(const Constant(true))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get finishedAt => dateTime().nullable()();

  /// Duración de cada ronda en minutos (v4). Solo informativo: el tiempo
  /// no decide resultados, avisa al organizador.
  IntColumn get roundMinutes => integer().withDefault(const Constant(45))();
}

@DataClassName('TournamentPlayer')
@TableIndex(name: 'idx_tp_player', columns: {#playerId})
class TournamentPlayers extends Table with SyncColumns {
  @override
  Set<Column<Object>> get primaryKey => {id};

  TextColumn get tournamentId => text().references(Tournaments, #id)();
  TextColumn get playerId => text().references(Players, #id)();

  /// Mazo declarado al inscribirse (cada match guarda además su propia copia).
  TextColumn get deckId => text().nullable().references(Decks, #id)();
  BoolColumn get dropped => boolean().withDefault(const Constant(false))();
  IntColumn get dropRound => integer().nullable()();

  /// Posición al terminar el Swiss (sirve para sembrar el Top Cut).
  IntColumn get swissPosition => integer().nullable()();

  /// Posición final del torneo (Top Cut primero, luego el resto por Swiss).
  IntColumn get finalPosition => integer().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {tournamentId, playerId},
      ];
}

@DataClassName('Round')
class Rounds extends Table with SyncColumns {
  @override
  Set<Column<Object>> get primaryKey => {id};

  TextColumn get tournamentId => text().references(Tournaments, #id)();
  IntColumn get number => integer()();
  TextColumn get phase => textEnum<RoundPhase>()();

  /// Solo Top Cut: jugadores vivos al empezar la ronda (32, 16, 8, 4, 2).
  IntColumn get bracketSize => integer().nullable()();
  TextColumn get status =>
      textEnum<RoundStatus>().withDefault(const Constant('open'))();

  /// Cuándo se puso en marcha el reloj de la ronda (v4). null = sin iniciar.
  DateTimeColumn get timerStartedAt => dateTime().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {tournamentId, number},
      ];
}

/// Fuente de verdad de TODAS las estadísticas (jugador, mazo, ranking).
@DataClassName('Match')
@TableIndex(name: 'idx_match_tournament', columns: {#tournamentId})
@TableIndex(name: 'idx_match_round', columns: {#roundId})
@TableIndex(name: 'idx_match_p1', columns: {#player1Id})
@TableIndex(name: 'idx_match_p2', columns: {#player2Id})
@TableIndex(name: 'idx_match_d1', columns: {#deck1Id})
@TableIndex(name: 'idx_match_d2', columns: {#deck2Id})
class Matches extends Table with SyncColumns {
  @override
  Set<Column<Object>> get primaryKey => {id};

  TextColumn get tournamentId => text().references(Tournaments, #id)();
  TextColumn get roundId => text().references(Rounds, #id)();
  IntColumn get tableNumber => integer().nullable()();
  TextColumn get player1Id => text().references(Players, #id)();

  /// null = BYE (player1 gana automáticamente).
  TextColumn get player2Id => text().nullable().references(Players, #id)();

  /// Mazo usado EN ESTE match (copia; no cambia si luego se edita la inscripción).
  TextColumn get deck1Id => text().nullable().references(Decks, #id)();
  TextColumn get deck2Id => text().nullable().references(Decks, #id)();
  TextColumn get result =>
      textEnum<MatchResult>().withDefault(const Constant('pending'))();
  BoolColumn get isBye => boolean().withDefault(const Constant(false))();
  BoolColumn get isThirdPlace => boolean().withDefault(const Constant(false))();
  DateTimeColumn get reportedAt => dateTime().nullable()();

  /// Marcador al mejor de 3: juegos ganados J1 - juegos empatados - juegos ganados J2.
  /// null mientras el match está pendiente. `result` se deriva de aquí.
  IntColumn get games1 => integer().nullable()();
  IntColumn get gamesDraw => integer().nullable()();
  IntColumn get games2 => integer().nullable()();
}

// ───────────────────────────── Ranking ─────────────────────────────

/// Puntos de ranking que un jugador obtuvo en un torneo terminado.
/// El ranking trimestral activo = SUM(points) agrupado por jugador y temporada.
@DataClassName('SeasonResult')
@TableIndex(name: 'idx_sr_season', columns: {#seasonId})
class SeasonResults extends Table with SyncColumns {
  @override
  Set<Column<Object>> get primaryKey => {id};

  TextColumn get seasonId => text().references(Seasons, #id)();
  TextColumn get tournamentId => text().references(Tournaments, #id)();
  TextColumn get playerId => text().references(Players, #id)();
  IntColumn get position => integer()();
  IntColumn get points => integer()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {tournamentId, playerId},
      ];
}

/// Foto congelada del ranking de jugadores al cerrar una temporada.
@DataClassName('RankingSnapshot')
class RankingSnapshots extends Table with SyncColumns {
  @override
  Set<Column<Object>> get primaryKey => {id};

  TextColumn get seasonId => text().references(Seasons, #id)();
  TextColumn get playerId => text().references(Players, #id)();
  IntColumn get rank => integer()();
  IntColumn get points => integer()();

  /// JSON con partidas, V/D/E, winrate, torneos, mejor posición, último mazo.
  TextColumn get statsJson => text()();
}

/// Foto congelada del Top de Mazos al cerrar una temporada.
@DataClassName('DeckSnapshot')
class DeckSnapshots extends Table with SyncColumns {
  @override
  Set<Column<Object>> get primaryKey => {id};

  TextColumn get seasonId => text().references(Seasons, #id)();
  TextColumn get deckId => text().references(Decks, #id)();
  IntColumn get rank => integer()();
  RealColumn get score => real()();

  /// JSON con PP, WRp, V/D/E Swiss y Top, entradas al Top, títulos, mejor resultado.
  TextColumn get statsJson => text()();
}
