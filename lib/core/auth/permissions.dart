import 'account.dart';

/// Qué puede ver y hacer quien usa el teléfono, según su rol y su licencia
/// (tabla "Qué ve cada uno" del plan online).
///
/// - **Modo local** (sin cuenta): el teléfono funciona como hasta ahora, como
///   el del organizador que lleva los torneos: todo permitido.
/// - Lo propio es siempre gratis: su ficha, sus torneos (abiertos o
///   terminados), el ranking y la tier list.
/// - La licencia da las estadísticas de todos los mazos y, al organizador,
///   llevar torneos. Los jueces usan la licencia del organizador del torneo.
/// - Solo el administrador ve todas las fichas y la lista de jugadores.
class Permissions {
  const Permissions({
    required this.role,
    required this.hasLicense,
    this.playerId,
    this.local = false,
  });

  /// Sin cuenta: todo permitido (como hasta ahora).
  const Permissions.local()
      : role = AppRole.admin,
        hasLicense = true,
        playerId = null,
        local = true;

  final AppRole role;
  final bool hasLicense;

  /// Ficha vinculada a la cuenta.
  final String? playerId;
  final bool local;

  bool get isAdmin => local || role == AppRole.admin;
  bool get _organizer => role == AppRole.organizer && hasLicense;

  /// Ranking de la temporada y tier list: todos.
  bool get canSeeRanking => true;
  bool get canSeeTierList => true;

  /// Lista de todos los jugadores (pestaña Jugadores).
  bool get canSeeAllPlayers => isAdmin;

  /// Ficha completa de un jugador: la propia siempre, las demás solo el
  /// administrador.
  bool canSeePlayerProfile(String id) => isAdmin || (playerId != null && id == playerId);

  /// Estadísticas de todos los mazos (matriz de enfrentamientos y ficha de
  /// cada mazo).
  bool get canSeeDeckStats => isAdmin || hasLicense;

  /// Crear torneos y llevar los propios.
  bool get canCreateTournaments => isAdmin || _organizer;

  /// Ver un torneo: el administrador todos; el organizador los suyos; el
  /// juez aquellos donde lo añadieron; el jugador aquellos donde está (o
  /// estuvo) inscrito.
  bool canSeeTournament({
    bool isOwner = false,
    bool isJudge = false,
    bool isEnrolled = false,
  }) =>
      isAdmin || isOwner || isJudge || isEnrolled;

  /// Configurar el torneo (inscripción, rondas, cerrar…): su organizador.
  bool canManageTournament({required bool isOwner}) => isAdmin || (_organizer && isOwner);

  /// Reportar resultados y poner penalizaciones: el organizador del torneo y
  /// sus jueces.
  bool canReportResults({required bool isOwner, bool isJudge = false}) =>
      canManageTournament(isOwner: isOwner) || isJudge;

  /// Inscribir: el organizador solo busca jugadores dentro de la inscripción
  /// de su torneo (ve el nombre, no la ficha).
  bool canSearchPlayersToEnroll({required bool isOwner}) => canManageTournament(isOwner: isOwner);

  /// Copias .gtcg: el administrador y los organizadores.
  bool get canBackup => isAdmin || role == AppRole.organizer;

  /// Cuentas y roles.
  bool get canManageAccounts => isAdmin && !local;
}
