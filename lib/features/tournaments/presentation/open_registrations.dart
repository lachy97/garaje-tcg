import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../core/auth/account.dart';
import '../../../core/db/database_provider.dart';
import '../../../core/registrations/registrations.dart';
import '../../../core/sync/sync_service.dart';
import '../../decks/presentation/deck_picker.dart';
import 'providers.dart';

/// Último mazo con el que jugó la ficha vinculada (para proponerlo).
final _myLastDeckProvider = FutureProvider.autoDispose.family<String?, String>((ref, playerId) async {
  final decks = await ref.read(tournamentsDaoProvider).lastDecks();
  return decks[playerId]?.name;
});

/// Torneos con la inscripción desde la app abierta (teléfono del jugador):
/// pedir plaza con su mazo, ver el estado y borrarse.
class OpenRegistrationsSection extends ConsumerWidget {
  const OpenRegistrationsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(myRegistrationsProvider);
    return data.when(
      skipLoadingOnReload: true,
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sin conexión con el servidor: no se ven los torneos con inscripción '
                'abierta (¿VPN activada?).',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(myRegistrationsProvider),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
      data: (mine) {
        if (mine == null || mine.open.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionLabel('Inscripción abierta (${mine.open.length})'),
            for (final t in mine.open)
              _OpenTournamentCard(tournament: t, request: mine.requests[t.id], playerId: mine.playerId),
          ],
        );
      },
    );
  }
}

class _OpenTournamentCard extends ConsumerStatefulWidget {
  const _OpenTournamentCard({required this.tournament, required this.request, required this.playerId});

  final OpenTournament tournament;
  final RegistrationRequest? request;
  final String? playerId;

  @override
  ConsumerState<_OpenTournamentCard> createState() => _OpenTournamentCardState();
}

class _OpenTournamentCardState extends ConsumerState<_OpenTournamentCard> {
  bool _busy = false;

  OpenTournament get t => widget.tournament;

  Future<void> _run(Future<void> Function() action, String ok) async {
    if (_busy) return;
    setState(() => _busy = true);
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
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(myRegistrationsProvider);
        // Baja los datos nuevos (p. ej. la inscripción ya hecha).
        ref.read(syncControllerProvider.notifier).sync();
      }
    }
  }

  Future<void> _request() => _run(() async {
        final pid = widget.playerId;
        final last = pid == null ? null : await ref.read(_myLastDeckProvider(pid).future);
        if (!mounted) return;
        final deck = await showDeckPicker(context, current: widget.request?.deckName ?? last);
        if (deck == null) throw const ActionCancelled();
        await ref.read(registrationsApiProvider)!.request(t.id, deck);
      }, widget.request?.status == RegistrationStatus.pending ? 'Mazo cambiado' : 'Solicitud enviada');

  Future<void> _cancel(RegistrationRequest r) => _run(() async {
        final ok = await confirmDialog(
          context,
          title: r.status == RegistrationStatus.registered ? 'Borrarme del torneo' : 'Cancelar solicitud',
          message: r.status == RegistrationStatus.registered
              ? 'Te quitarán de la lista de inscritos de "${t.name}".'
              : 'Se retira tu solicitud para "${t.name}".',
          confirm: r.status == RegistrationStatus.registered ? 'Borrarme' : 'Cancelar solicitud',
          danger: true,
        );
        if (!ok) throw const ActionCancelled();
        await ref.read(registrationsApiProvider)!.cancel(r.id);
      }, 'Listo');

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final pid = widget.playerId;
    final enrolledIds =
        pid == null ? const <String>{} : ref.watch(playerTournamentIdsProvider(pid)).value ?? const <String>{};
    final enrolled = enrolledIds.contains(t.id);
    final status = r?.status;
    final date = t.date == null ? '' : '${DateFormat.yMMMd('es').format(t.date!)} · ';
    final info = '$date${t.swissRounds ?? '?'} rondas · '
        '${t.topCutSize == 0 ? 'sin Top' : 'Top ${t.topCutSize}'} · '
        '${t.capacity == null ? '${t.enrolled} inscrito(s)' : '${t.enrolled}/${t.capacity} plazas'}';

    final (String? line, Color color) = switch (status) {
      _ when enrolled || status == RegistrationStatus.registered => (
          '✓ Estás inscrito${r?.deckName == null ? '' : ' con ${r!.deckName}'}',
          AppColors.neon
        ),
      RegistrationStatus.pending => ('Solicitud enviada con ${r!.deckName}: espera al organizador.', AppColors.draw),
      RegistrationStatus.accepted => (
          'Aceptada con ${r!.deckName}: quedarás inscrito cuando sincronice el organizador.',
          AppColors.leaf
        ),
      RegistrationStatus.waitlist => (
          'Cupo lleno: estás en la lista de espera (puesto ${r!.waitPosition ?? '?'}). '
              'Si se libera una plaza, entras solo.',
          AppColors.draw
        ),
      RegistrationStatus.cancelRequested => ('Baja pedida: el organizador te quitará.', AppColors.draw),
      RegistrationStatus.rejected => (
          'Rechazada${r!.reason == null ? '' : ': ${r!.reason!}'}.',
          AppColors.loss
        ),
      _ => (null, AppColors.textSecondary),
    };

    final canRequest = !enrolled &&
        (status == null || status == RegistrationStatus.rejected || status == RegistrationStatus.cancelled);
    final canCancel = r != null &&
        (status == RegistrationStatus.pending ||
            status == RegistrationStatus.waitlist ||
            status == RegistrationStatus.accepted ||
            (status == RegistrationStatus.registered && enrolled));

    return NeonCard(
      glow: canRequest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.how_to_reg, color: AppColors.neon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name, style: Theme.of(context).textTheme.titleMedium),
                    Text(info, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          if (line != null) ...[
            const SizedBox(height: 8),
            Text(line, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          ],
          if (enrolled && r == null) ...[
            const SizedBox(height: 4),
            Text('Para borrarte o cambiar el mazo, habla con el organizador.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
          if (canRequest && t.full) ...[
            const SizedBox(height: 6),
            Text('Torneo completo: si te inscribes, quedas en la lista de espera.',
                style: TextStyle(fontSize: 12, color: AppColors.draw)),
          ],
          if (canRequest && pid == null) ...[
            const SizedBox(height: 6),
            Text(
              'Tu cuenta aún no tiene ficha de jugador: el organizador la elegirá al aceptarte.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (canRequest || canCancel) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (canCancel)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _cancel(r!),
                      child: Text(status == RegistrationStatus.registered ? 'Borrarme' : 'Cancelar',
                          style: TextStyle(color: AppColors.loss)),
                    ),
                  ),
                if (canCancel && (status == RegistrationStatus.pending || status == RegistrationStatus.waitlist))
                  const SizedBox(width: 10),
                if (status == RegistrationStatus.pending || status == RegistrationStatus.waitlist)
                  Expanded(
                    child: OutlinedButton(onPressed: _request, child: const Text('Cambiar mazo')),
                  ),
                if (canRequest)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _request,
                      icon: const Icon(Icons.how_to_reg),
                      label: Text(status == null ? 'Inscribirme' : 'Volver a pedir'),
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
