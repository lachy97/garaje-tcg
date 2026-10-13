import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../app/theme.dart';
import '../../core/backup/backup_codec.dart';
import '../../core/backup/backup_merge.dart';

/// Vista previa de una importación: qué pasará con cada torneo de la copia,
/// con la opción de cambiarlo. Devuelve true si se confirma.
Future<bool> showMergePreview(
  BuildContext context, {
  required BackupHeader header,
  required MergePlan plan,
}) async {
  final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _MergePreviewPage(header: header, plan: plan),
  ));
  return ok ?? false;
}

String _actionLabel(MergeAction a) => switch (a) {
      MergeAction.add => 'Añadir',
      MergeAction.replace => 'Reemplazar',
      MergeAction.skip => 'No importar',
    };

class _MergePreviewPage extends StatefulWidget {
  const _MergePreviewPage({required this.header, required this.plan});

  final BackupHeader header;
  final MergePlan plan;

  @override
  State<_MergePreviewPage> createState() => _MergePreviewPageState();
}

class _MergePreviewPageState extends State<_MergePreviewPage> {
  final _day = DateFormat('dd/MM/yyyy');

  String _date(DateTime? d) => d == null ? '?' : _day.format(d.toLocal());

  /// Explicación de la situación de cada torneo.
  (String, Color) _situation(MergeItem i) {
    final newer = i.localNewer
        ? ' El de este teléfono tiene cambios MÁS RECIENTES que el de la copia.'
        : '';
    return switch (i.kind) {
      MergeKind.newTournament => ('Torneo nuevo en este teléfono.', AppColors.neon),
      MergeKind.sameTournament => (
          'Ya está en este teléfono (es el mismo torneo).$newer',
          i.localNewer ? AppColors.draw : AppColors.textSecondary,
        ),
      MergeKind.sameNameSameDate => (
          'Hay uno con el mismo nombre y la misma fecha.$newer',
          i.localNewer ? AppColors.draw : AppColors.textSecondary,
        ),
      MergeKind.sameNameOtherDate => (
          'Hay otro con el mismo nombre del ${_date(i.localDate)}: '
              'probablemente es OTRO torneo.',
          AppColors.draw,
        ),
      MergeKind.deletedHere => ('Se borró en este teléfono.', AppColors.draw),
      MergeKind.lockedSeason => (
          'Es de una temporada cerrada en este teléfono: no se importa.',
          AppColors.textDisabled,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.header;
    final items = widget.plan.items;
    final count = {
      for (final a in MergeAction.values) a: items.where((i) => i.action == a).length,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('IMPORTAR DATOS')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Text(
            'Copia del ${DateFormat('dd/MM/yyyy HH:mm').format(h.exportedAt)} · '
            '${h.players} jugadores · ${h.tournaments} torneos · ${h.decks} mazos',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          const Text(
            'Revisa qué se hará con cada torneo de la copia. Los jugadores y mazos '
            'nuevos se añaden; no se borra nada que no elijas reemplazar. Antes se '
            'guarda una copia automática por si necesitas volver atrás.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Text('La copia no tiene torneos. Solo se añadirán jugadores y mazos.',
                  textAlign: TextAlign.center),
            ),
          for (final i in items) _item(i),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${count[MergeAction.add]} añadir · ${count[MergeAction.replace]} reemplazar · '
                '${count[MergeAction.skip]} sin importar',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Importar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(MergeItem i) {
    final (text, color) = _situation(i);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: i.action == MergeAction.skip ? AppColors.outline : AppColors.neon,
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(i.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          Text(_date(i.date), style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(text, style: TextStyle(fontSize: 13, color: color)),
          const SizedBox(height: 8),
          if (i.allowed.length == 1)
            Text(_actionLabel(i.action),
                style: const TextStyle(fontWeight: FontWeight.w700))
          else
            SegmentedButton<MergeAction>(
              showSelectedIcon: false,
              segments: [
                for (final a in i.allowed)
                  ButtonSegment(value: a, label: Text(_actionLabel(a))),
              ],
              selected: {i.action},
              onSelectionChanged: (s) => setState(() => i.action = s.first),
            ),
        ],
      ),
    );
  }
}
