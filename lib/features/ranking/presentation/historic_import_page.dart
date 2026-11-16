import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/database_provider.dart';
import '../../../core/sync/sync_service.dart';
import '../../players/presentation/players_page.dart' show playersProvider;
import '../data/historic_seasons.dart';

/// Modo administrador: importar el ranking final de T1, T2 y T3 2026 (de los
/// Excel). Antes se revisa a qué ficha va cada nombre: la que ya existe con
/// ese apodo o una ficha nueva. Tocar un nombre para cambiarlo.
class HistoricImportPage extends ConsumerStatefulWidget {
  const HistoricImportPage({super.key});

  @override
  ConsumerState<HistoricImportPage> createState() => _HistoricImportPageState();
}

class _HistoricImportPageState extends ConsumerState<HistoricImportPage> {
  /// Clave del nombre → id de ficha (null = ficha nueva). Se rellena con la
  /// propuesta la primera vez que hay fichas.
  Map<String, String?>? _targets;
  bool _busy = false;

  Future<void> _import(Map<String, String?> targets) async {
    // La web solo baja datos: se importa desde la app de Android (la sube).
    if (kIsWeb) {
      showMessage(context, 'Impórtalo desde la app de Android: la web no sube datos.', error: true);
      return;
    }
    final news = targets.values.where((v) => v == null).length;
    final ok = await confirmDialog(
      context,
      title: 'Importar T1, T2 y T3 2026',
      message: 'Se guardan como temporadas cerradas con su ranking final '
          '(${historicSeasons.fold<int>(0, (n, s) => n + s.rows.length)} filas), sin partidas ni mazos. '
          '${news == 0 ? 'Todos los nombres van a fichas existentes.' : 'Se crean $news fichas nuevas.'}'
          '\n\nSi ya se importaron, se reemplazan.',
      confirm: 'Importar',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final n = await importHistoricSeasons(ref.read(databaseProvider), targets);
      // Se sube enseguida: llega a todos al sincronizar.
      await ref.read(syncControllerProvider.notifier).sync();
      if (mounted) {
        showMessage(context, '$n filas importadas');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showMessage(context, 'No se pudo importar: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(String key, List<Player> players) async {
    final chosen = await showModalBottomSheet<(bool, Player?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PlayerChooser(name: key, players: players),
    );
    if (chosen == null) return;
    setState(() => _targets![key] = chosen.$1 ? null : chosen.$2!.id);
  }

  @override
  Widget build(BuildContext context) {
    final players = ref.watch(playersProvider('')).value;
    if (players == null) {
      return Scaffold(appBar: AppBar(title: const Text('TEMPORADAS ANTERIORES')), body: const Center(child: CircularProgressIndicator()));
    }
    final targets = _targets ??= {
      for (final e in proposeHistoricMatches(players).entries) e.key: e.value?.id,
    };
    final byId = {for (final p in players) p.id: p};
    final keys = targets.keys.toList()..sort();
    final news = targets.values.where((v) => v == null).length;
    return Scaffold(
      appBar: AppBar(title: const Text('TEMPORADAS ANTERIORES')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Ranking final de T1, T2 y T3 2026 (Excel). ${keys.length} jugadores: '
              '${keys.length - news} con ficha existente y $news con ficha nueva. '
              'Revisa los nombres: toca uno para elegir otra ficha.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          for (final k in keys)
            ListTile(
              dense: true,
              title: Text(k, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([
                targets[k] == null
                    ? 'Ficha nueva: ${historicNickname(k)}'
                    : '→ ${byId[targets[k]]?.nickname ?? '?'}',
                if (k == 'LACHY') 'también "LACHY PROWA" (T3)',
                if (k == 'MIGUEL V.') 'también "MIGUEL VITILIGO" (T3)',
              ].join(' · ')),
              trailing: Icon(targets[k] == null ? Icons.person_add_alt_1 : Icons.link,
                  color: targets[k] == null ? AppColors.draw : AppColors.neon),
              onTap: () => _pick(k, players),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _busy
              ? const Center(heightFactor: 1, child: CircularProgressIndicator())
              : FilledButton.icon(
                  onPressed: () => _import(targets),
                  icon: const Icon(Icons.download_done),
                  label: const Text('Importar las 3 temporadas'),
                ),
        ),
      ),
    );
  }
}

/// Elegir ficha existente (búsqueda) o "Ficha nueva". Devuelve (nueva, ficha).
class _PlayerChooser extends StatefulWidget {
  const _PlayerChooser({required this.name, required this.players});

  final String name;
  final List<Player> players;

  @override
  State<_PlayerChooser> createState() => _PlayerChooserState();
}

class _PlayerChooserState extends State<_PlayerChooser> {
  late final _q = TextEditingController(text: widget.name.split(' ').first.toLowerCase());

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final list = [
      for (final p in widget.players)
        if (p.deletedAt == null &&
            (q.isEmpty || p.nickname.toLowerCase().contains(q) || (p.fullName ?? '').toLowerCase().contains(q)))
          p,
    ];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _q,
              decoration: InputDecoration(labelText: 'Ficha para "${widget.name}"', prefixIcon: const Icon(Icons.search)),
              onChanged: (_) => setState(() {}),
            ),
          ),
          ListTile(
            leading: Icon(Icons.person_add_alt_1, color: AppColors.draw),
            title: Text('Ficha nueva: ${historicNickname(widget.name)}'),
            onTap: () => Navigator.pop(context, (true, null)),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: [
                for (final p in list)
                  ListTile(
                    title: Text(p.nickname),
                    subtitle: p.fullName == null ? null : Text(p.fullName!),
                    onTap: () => Navigator.pop(context, (false, p)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
