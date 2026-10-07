import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../core/db/database_provider.dart';
import '../domain/tournament_rules.dart';

class CreateTournamentPage extends ConsumerStatefulWidget {
  const CreateTournamentPage({super.key});

  @override
  ConsumerState<CreateTournamentPage> createState() => _CreateTournamentPageState();
}

class _CreateTournamentPageState extends ConsumerState<CreateTournamentPage> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(
      text: 'Torneo ${DateFormat('dd/MM', 'es').format(DateTime.now())}');
  DateTime _date = DateTime.now();
  int _rounds = 3;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
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
          );
      if (mounted) context.pushReplacement('/torneos/${t.id}');
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
                  const Icon(Icons.edit_calendar, color: AppColors.textSecondary),
                ],
              ),
            ),
            const SectionLabel('Rondas Swiss antes del Top Cut'),
            NeonCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: NumberStepper(
                      value: _rounds,
                      min: TournamentRules.minSwissRounds,
                      max: TournamentRules.maxSwissRounds,
                      onChanged: (v) => setState(() => _rounds = v),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Se puede ajustar después de inscribir a los jugadores: la app '
                    'sugiere las rondas y el Top Cut según la asistencia.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: const Text('CREAR TORNEO'),
            ),
          ],
        ),
      ),
    );
  }
}
