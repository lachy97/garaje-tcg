import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../core/db/database_provider.dart';
import '../domain/tournament_names.dart';
import '../domain/tournament_rules.dart';
import 'start_time.dart';
import 'tabs/rounds_tab.dart' show TopCutSelector;

class CreateTournamentPage extends ConsumerStatefulWidget {
  const CreateTournamentPage({super.key});

  @override
  ConsumerState<CreateTournamentPage> createState() => _CreateTournamentPageState();
}

class _CreateTournamentPageState extends ConsumerState<CreateTournamentPage> {
  final _formKey = GlobalKey<FormState>();
  // Nombre por defecto: "Torneo #N · T4 2026" (el siguiente de la temporada
  // de la fecha elegida). Se recalcula al cambiar la fecha mientras no se
  // escriba otro a mano.
  final _name = TextEditingController();
  bool _nameEdited = false;
  // Hoy a las 14:00 (se cambia abajo).
  DateTime _date = () {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, 14);
  }();

  @override
  void initState() {
    super.initState();
    _suggestName();
  }

  Future<void> _suggestName() async {
    if (_nameEdited) return;
    final all = await ref.read(tournamentsDaoProvider).watchAll().first;
    if (!mounted || _nameEdited) return;
    _name.text = nextTournamentName(all, _date);
  }
  int _rounds = 3;
  int _topCut = 0;
  int _minutes = TournamentRules.defaultRoundMinutes;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await pickStartDay(context, _date);
    if (d != null) {
      setState(() => _date = d);
      await _suggestName();
    }
  }

  Future<void> _pickTime() async {
    final d = await pickStartTime(context, _date);
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      final t = await ref.read(tournamentsDaoProvider).createTournament(
            name: _name.text,
            date: _date,
            swissRounds: _rounds,
            topCutSize: _topCut,
            roundMinutes: _minutes,
          );
      if (mounted) context.pushReplacement('/torneos/${t.id}');
    } catch (e) {
      if (mounted) showMessage(context, 'No se pudo crear el torneo: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NUEVO TORNEO')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => _nameEdited = true,
              decoration: const InputDecoration(
                labelText: 'Nombre del torneo',
                prefixIcon: Icon(Icons.emoji_events_outlined),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe un nombre' : null,
            ),
            const SizedBox(height: 12),
            NeonCard(
              onTap: _pickDate,
              child: Row(
                children: [
                  const Icon(Icons.event),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(DateFormat.yMMMMEEEEd('es').format(_date),
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Icon(Icons.edit_calendar, color: AppColors.textSecondary),
                ],
              ),
            ),
            const SizedBox(height: 8),
            NeonCard(
              onTap: _pickTime,
              child: Row(
                children: [
                  const Icon(Icons.schedule),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Empieza a las ${DateFormat.Hm('es').format(_date)}',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Icon(Icons.edit, color: AppColors.textSecondary),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(
                'Desde esa hora los jugadores ya no pueden inscribirse ni darse de baja desde la app.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            const SectionLabel('Rondas Swiss antes del Top Cut'),
            NeonCard(
              child: Center(
                child: NumberStepper(
                  value: _rounds,
                  min: TournamentRules.minSwissRounds,
                  max: TournamentRules.maxSwissRounds,
                  onChanged: (v) => setState(() => _rounds = v),
                ),
              ),
            ),
            const SectionLabel('Top Cut'),
            NeonCard(
              child: TopCutSelector(
                value: _topCut,
                onChanged: (v) => setState(() => _topCut = v),
              ),
            ),
            const SectionLabel('Tiempo por ronda'),
            NeonCard(
              child: Center(
                child: NumberStepper(
                  value: _minutes,
                  min: TournamentRules.minRoundMinutes,
                  max: TournamentRules.maxRoundMinutes,
                  step: 5,
                  suffix: 'min',
                  onChanged: (v) => setState(() => _minutes = v),
                ),
              ),
            ),
            const SectionLabel('Sugerencia según asistencia'),
            NeonCard(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _SuggestionTable(
                rounds: _rounds,
                topCut: _topCut,
                onPick: (rounds, top) => setState(() {
                  _rounds = rounds;
                  _topCut = top;
                }),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                'Toca una fila para usar esa configuración. Se puede cambiar mientras '
                'inscribes jugadores; al generar la ronda 1 queda fija.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      // Botón siempre visible (sin tener que bajar hasta el final).
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('CREAR TORNEO'),
          ),
        ),
      ),
    );
  }
}

/// Tabla de referencia: rondas y Top Cut sugeridos según asistencia.
/// Tocar una fila aplica esa configuración; la que coincide se resalta.
class _SuggestionTable extends StatelessWidget {
  const _SuggestionTable({required this.rounds, required this.topCut, required this.onPick});

  final int rounds;
  final int topCut;
  final void Function(int rounds, int topCut) onPick;

  static const _rows = [
    ('6 – 8', 3, 4),
    ('9 – 14', 4, 4),
    ('15 – 16', 4, 8),
    ('17 – 23', 5, 8),
    ('24 – 32', 5, 16),
    ('33 – 47', 6, 16),
    ('48 – 64', 6, 32),
  ];

  @override
  Widget build(BuildContext context) {
    final head = TextStyle(
        fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary);
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            Expanded(child: Text('JUGADORES', style: head)),
            Expanded(child: Text('RONDAS', style: head, textAlign: TextAlign.center)),
            Expanded(child: Text('TOP CUT', style: head, textAlign: TextAlign.end)),
          ]),
        ),
        const SizedBox(height: 4),
        for (final (players, r, top) in _rows)
          Material(
            color: r == rounds && top == topCut
                ? AppColors.forest.withValues(alpha: 0.6)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onPick(r, top),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(children: [
                  Expanded(child: Text(players)),
                  Expanded(child: Text('$r', textAlign: TextAlign.center)),
                  Expanded(child: Text('Top $top', textAlign: TextAlign.end)),
                ]),
              ),
            ),
          ),
      ],
    );
  }
}
