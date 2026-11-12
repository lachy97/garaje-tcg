import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../app/widgets/brand.dart';
import '../../../../app/widgets/common.dart';
import '../../../../core/auth/account.dart';
import '../../../../core/auth/auth_providers.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/db/database_provider.dart';
import '../../../../core/registrations/registrations.dart';
import '../../../../core/sync/sync_service.dart';
import '../../../players/presentation/players_page.dart' show playersProvider;

/// Inscripción desde la app (organizador, torneo en inscripción): abrirla,
/// elegir si las solicitudes se aceptan solas o a mano, y ver las solicitudes.
class OnlineRegistrationCard extends ConsumerWidget {
  const OnlineRegistrationCard({super.key, required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tournament;
    final api = ref.watch(registrationsApiProvider);
    final perms = ref.watch(permissionsProvider);
    if (api == null || t.status != TournamentStatus.draft || !perms.canManageTournament(isOwner: true)) {
      return const SizedBox.shrink();
    }
    final requests = t.onlineRegistration
        ? ref.watch(tournamentRequestsProvider(t.id))
        : const AsyncData(<RegistrationRequest>[]);
    final list = requests.value ?? const <RegistrationRequest>[];
    final pending = list.where((r) => r.status == RegistrationStatus.pending).length;

    Future<void> save({bool? online, bool? auto}) async {
      await ref
          .read(tournamentsDaoProvider)
          .updateSettings(t.id, onlineRegistration: online, autoAccept: auto);
      // Se publica en el servidor enseguida (si hay conexión).
      await ref.read(syncControllerProvider.notifier).sync();
      ref.invalidate(tournamentRequestsProvider(t.id));
    }

    return NeonCard(
      glow: pending > 0,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.phone_android, color: AppColors.neon),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Inscripción desde la app',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    Text(
                      t.onlineRegistration
                          ? 'Los jugadores piden plaza desde su teléfono.'
                          : 'Cerrada: solo inscribes tú.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch(
                value: t.onlineRegistration,
                onChanged: (v) => runGuarded(context, () => save(online: v)),
              ),
            ],
          ),
          if (t.onlineRegistration) ...[
            const SizedBox(height: 10),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.pan_tool_alt_outlined), label: Text('A mano')),
                ButtonSegment(value: true, icon: Icon(Icons.bolt), label: Text('Se aceptan solas')),
              ],
              selected: {t.autoAccept},
              showSelectedIcon: false,
              onSelectionChanged: (s) => runGuarded(context, () => save(auto: s.first)),
            ),
            const SizedBox(height: 6),
            Text(
              t.autoAccept
                  ? 'Las cuentas con ficha vinculada quedan inscritas solas al sincronizar. '
                      'Las que no tienen ficha esperan a que elijas cuál es la suya.'
                  : 'Cada solicitud espera a que la aceptes o la rechaces.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => FractionallySizedBox(
                  heightFactor: 0.85,
                  child: RequestsSheet(tournament: t),
                ),
              ),
              icon: requests.isLoading && !requests.hasValue
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.inbox_outlined),
              label: Text(requests.hasError
                  ? 'Solicitudes (sin conexión)'
                  : pending > 0
                      ? 'Solicitudes · $pending pendiente(s)'
                      : 'Solicitudes (${list.length})'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Lista de solicitudes con aceptar / rechazar.
class RequestsSheet extends ConsumerStatefulWidget {
  const RequestsSheet({super.key, required this.tournament});

  final Tournament tournament;

  @override
  ConsumerState<RequestsSheet> createState() => _RequestsSheetState();
}

class _RequestsSheetState extends ConsumerState<RequestsSheet> {
  /// Solicitud en curso (para el indicador y evitar dobles toques).
  String? _busy;

  Tournament get t => widget.tournament;

  void _refresh() => ref.invalidate(tournamentRequestsProvider(t.id));

  Future<void> _run(RegistrationRequest r, Future<void> Function() action, String ok) async {
    if (_busy != null) return;
    setState(() => _busy = r.id);
    try {
      await action();
      if (mounted) showMessage(context, ok);
    } on ActionCancelled {
      // nada
    } on AuthException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) showMessage(context, 'No se pudo: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
      _refresh();
    }
  }

  /// Acepta e inscribe en este teléfono. Sin ficha vinculada: se elige (o se
  /// crea) y la cuenta queda vinculada a ella.
  Future<void> _accept(RegistrationRequest r) => _run(r, () async {
        final api = ref.read(registrationsApiProvider)!;
        final db = ref.read(databaseProvider);
        var playerId = r.linked ? r.playerId : null;
        if (playerId == null) {
          final picked = await _pickPlayer(r);
          if (picked == null) throw const ActionCancelled();
          playerId = picked;
        } else if (await db.playersDao.getById(playerId) == null) {
          throw AuthException('La ficha de @${r.username} no está en este teléfono.');
        }
        await api.accept(r.id, playerId: playerId);
        await db.tournamentsDao.registerPlayer(t.id, playerId, deckName: r.deckName);
        await api.done(r.id);
        await ref.read(syncControllerProvider.notifier).sync();
      }, '${r.nickname} inscrito');

  Future<void> _reject(RegistrationRequest r) => _run(r, () async {
        final reason = await _askReason(r);
        if (reason == null) throw const ActionCancelled();
        await ref.read(registrationsApiProvider)!.reject(r.id, reason: reason.isEmpty ? null : reason);
      }, 'Solicitud rechazada');

  Future<String?> _askReason(RegistrationRequest r) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        actionsOverflowButtonSpacing: 10,
        title: Text('Rechazar a ${r.nickname}'),
        content: TextField(
          controller: c,
          maxLength: 200,
          decoration: const InputDecoration(
            labelText: 'Motivo (opcional)',
            hintText: 'Ej.: cupo lleno',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.loss),
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
  }

  /// Ficha para una cuenta sin vincular: una existente o una nueva.
  Future<String?> _pickPlayer(RegistrationRequest r) => showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => FractionallySizedBox(
          heightFactor: 0.8,
          child: _PickPlayer(request: r),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(tournamentRequestsProvider(t.id));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text('SOLICITUDES',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1)),
              ),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncView(
            value: requests,
            builder: (list) {
              if (list.isEmpty) {
                return const EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'Sin solicitudes todavía',
                  subtitle: 'Los jugadores la piden desde Torneos → Inscripción abierta.',
                );
              }
              List<RegistrationRequest> of(Set<RegistrationStatus> s) =>
                  [for (final r in list) if (s.contains(r.status)) r];
              final pending = of({RegistrationStatus.pending});
              final waiting = of({RegistrationStatus.accepted, RegistrationStatus.cancelRequested});
              final done = of({RegistrationStatus.registered});
              final closed = of({RegistrationStatus.rejected, RegistrationStatus.cancelled});
              final linkedPending = [for (final r in pending) if (r.linked) r];
              return ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  if (pending.isNotEmpty) ...[
                    SectionLabel('Pendientes (${pending.length})'),
                    if (linkedPending.length > 1)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: FilledButton.icon(
                          onPressed: _busy != null
                              ? null
                              : () async {
                                  for (final r in linkedPending) {
                                    await _accept(r);
                                    if (!mounted) return;
                                  }
                                },
                          icon: const Icon(Icons.done_all),
                          label: Text('Aceptar las ${linkedPending.length} con ficha'),
                        ),
                      ),
                    for (final r in pending)
                      _RequestTile(
                        request: r,
                        busy: _busy == r.id,
                        onAccept: _busy == null ? () => _accept(r) : null,
                        onReject: _busy == null ? () => _reject(r) : null,
                      ),
                  ],
                  if (waiting.isNotEmpty) ...[
                    SectionLabel('Por aplicar en este teléfono (${waiting.length})'),
                    for (final r in waiting) _RequestTile(request: r),
                  ],
                  if (done.isNotEmpty) ...[
                    SectionLabel('Inscritos desde la app (${done.length})'),
                    for (final r in done) _RequestTile(request: r),
                  ],
                  if (closed.isNotEmpty) ...[
                    SectionLabel('Rechazadas o canceladas (${closed.length})'),
                    for (final r in closed) _RequestTile(request: r),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request, this.onAccept, this.onReject, this.busy = false});

  final RegistrationRequest request;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final (label, color) = switch (r.status) {
      RegistrationStatus.pending => ('Pendiente', AppColors.draw),
      RegistrationStatus.accepted => ('Aceptada · se inscribe al sincronizar', AppColors.leaf),
      RegistrationStatus.registered => ('Inscrito', AppColors.neon),
      RegistrationStatus.rejected => ('Rechazada${r.reason == null ? '' : ': ${r.reason}'}', AppColors.loss),
      RegistrationStatus.cancelRequested => ('Se borró · se quita al sincronizar', AppColors.draw),
      RegistrationStatus.cancelled => ('Cancelada por el jugador', AppColors.textSecondary),
    };
    final actions = onAccept != null || onReject != null || busy;
    return NeonCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${r.nickname} · @${r.username}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(
            [
              'Mazo: ${r.deckName ?? '—'}',
              if (!r.linked && r.status == RegistrationStatus.pending) 'sin ficha vinculada',
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          if (actions) ...[
            const SizedBox(height: 10),
            if (busy)
              const Center(child: CircularProgressIndicator())
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onReject,
                      child: Text('Rechazar', style: TextStyle(color: AppColors.loss)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: onAccept,
                      child: Text(r.linked ? 'Aceptar' : 'Elegir ficha y aceptar'),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

/// Elegir la ficha de una cuenta sin vincular (o crear una con su apodo).
class _PickPlayer extends ConsumerStatefulWidget {
  const _PickPlayer({required this.request});

  final RegistrationRequest request;

  @override
  ConsumerState<_PickPlayer> createState() => _PickPlayerState();
}

class _PickPlayerState extends ConsumerState<_PickPlayer> {
  late final _q = TextEditingController(text: widget.request.nickname);

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    try {
      final p = await ref.read(playersDaoProvider).create(nickname: widget.request.nickname);
      if (mounted) Navigator.pop(context, p.id);
    } catch (e) {
      if (mounted) showMessage(context, 'No se pudo crear la ficha: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final players = ref.watch(playersProvider('')).value ?? const <Player>[];
    final q = _q.text.trim().toLowerCase();
    final list = [
      for (final p in players)
        if (q.isEmpty ||
            p.nickname.toLowerCase().contains(q) ||
            (p.fullName ?? '').toLowerCase().contains(q))
          p,
    ];
    final exact = players.any((p) => p.nickname.toLowerCase() == r.nickname.toLowerCase());
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            '¿Cuál es la ficha de ${r.nickname} (@${r.username})? Su cuenta quedará '
            'vinculada a ella.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _q,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Buscar ficha'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (!exact)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: OutlinedButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.person_add_alt),
              label: Text('Es nuevo: crear ficha «${r.nickname}»'),
            ),
          ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('Ninguna ficha coincide'))
              : ListView(
                  children: [
                    for (final p in list)
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(p.nickname),
                        subtitle: p.fullName == null ? null : Text(p.fullName!),
                        onTap: () => Navigator.pop(context, p.id),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
