import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../app/widgets/brand.dart';
import '../../../../app/widgets/common.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/db/daos/tournaments_dao.dart';
import '../../../decks/presentation/deck_image.dart';
import '../../domain/models.dart';
import '../../domain/round_import.dart';
import '../../domain/swiss/swiss_pairing_engine.dart';
import '../providers.dart';

/// Ronda 1 con enfrentamientos definidos por el organizador: se toca un
/// jugador y luego su rival (o "BYE" si el número es impar). Los que queden
/// sin definir se emparejan al azar. A cada pareja se le puede elegir la mesa
/// (tocando "Mesa N"); si no, toma la libre más baja.
/// Devuelve las parejas (rival null = BYE) y las mesas elegidas (por el
/// primer jugador de la pareja), o null si se cancela.
///
/// También se pueden importar los cruces desde texto (botón de la barra), p. ej.
/// el de "Compartir ronda → Texto" o una lista escrita a mano.
class FirstRoundPairingPage extends ConsumerStatefulWidget {
  const FirstRoundPairingPage({
    super.key,
    required this.tournament,
    this.startWithImport = false,
    this.actionLabel = 'GENERAR RONDA 1',
  });

  final Tournament tournament;

  /// Abre directamente la importación desde texto.
  final bool startWithImport;

  /// Texto del botón final.
  final String actionLabel;

  @override
  ConsumerState<FirstRoundPairingPage> createState() => _FirstRoundPairingPageState();
}

class _FirstRoundPairingPageState extends ConsumerState<FirstRoundPairingPage> {
  final _pairs = <(String, String?)>[];

  /// Mesa elegida a mano para una pareja (clave: su primer jugador).
  final _tables = <String, int>{};
  String? _selected;
  String _query = '';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.startWithImport) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _import();
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Pega el texto de la ronda y rellena los enfrentamientos (reemplaza los
  /// que hubiera). Lo que no se reconozca queda sin definir (al azar).
  Future<void> _import() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => _ImportDialog(initial: clip?.text ?? ''),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    final all = await ref.read(registeredProvider(widget.tournament.id).future);
    if (!mounted) return;
    final players = all.where((r) => !r.entry.dropped).toList();
    final result = parseRoundText(text, [
      for (final r in players)
        ImportCandidate(id: r.player.id, nickname: r.player.nickname, fullName: r.player.fullName),
    ]);
    final problems = [...result.problems];
    var pairs = result.pairs;
    // Con número par de jugadores no hay BYE.
    if (players.length.isEven && pairs.any((p) => p.$2 == null)) {
      pairs = [for (final p in pairs) if (p.$2 != null) p];
      problems.add('Hay número par de jugadores: el BYE del texto no se usa.');
    }
    // Mesas fuera de rango: se asignan solas.
    final tableCount = players.length ~/ 2;
    final tables = <String, int>{};
    for (final MapEntry(:key, :value) in result.tables.entries) {
      if (value >= 1 && value <= tableCount) {
        tables[key] = value;
      } else {
        problems.add('La mesa $value no existe (hay $tableCount): se asigna otra.');
      }
    }
    setState(() {
      _pairs
        ..clear()
        ..addAll(pairs);
      _tables
        ..clear()
        ..addAll(tables);
      _selected = null;
    });
    final defined = {for (final (a, b) in pairs) ...[a, if (b != null) b]}.length;
    final left = players.length - defined;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        actionsOverflowButtonSpacing: 10,
        icon: Icon(
          pairs.isEmpty ? Icons.error_outline : Icons.check_circle_outline,
          color: pairs.isEmpty ? AppColors.loss : AppColors.neon,
          size: 36,
        ),
        title: Text(pairs.isEmpty
            ? 'No se reconoció ningún cruce'
            : '${pairs.length} enfrentamiento(s) importado(s)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(pairs.isEmpty
                  ? 'Cada línea debe ser como "Mesa 1: Ana vs Luis" o "BYE: Pedro", '
                      'con los apodos de los inscritos.'
                  : left == 0
                      ? 'Están todos los inscritos. Revisa los cruces y genera la ronda.'
                      : '$left inscrito(s) sin cruce en el texto: se emparejan al azar '
                          '(o tócalos para definirlos).'),
              for (final p in problems) ...[
                const SizedBox(height: 8),
                Text('• $p', style: TextStyle(color: AppColors.draw, fontSize: 13)),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Revisar')),
        ],
      ),
    );
  }

  bool get _hasBye => _pairs.any((p) => p.$2 == null);

  Set<String> get _used => {
        for (final (a, b) in _pairs) ...[a, if (b != null) b],
      };

  void _tap(String id) {
    setState(() {
      if (_selected == null) {
        _selected = id;
      } else if (_selected == id) {
        _selected = null;
      } else {
        _pairs.add((_selected!, id));
        _selected = null;
        _query = '';
        _search.clear();
      }
    });
  }

  void _giveBye() => setState(() {
        _pairs.add((_selected!, null));
        _selected = null;
      });

  @override
  Widget build(BuildContext context) {
    final registered = ref.watch(registeredProvider(widget.tournament.id));
    return Scaffold(
      appBar: AppBar(
        title: const Text('CRUCES DE LA RONDA 1'),
        actions: [
          IconButton(
            tooltip: 'Importar desde texto',
            icon: const Icon(Icons.content_paste_go),
            onPressed: _import,
          ),
        ],
      ),
      body: AsyncView(
        value: registered,
        builder: (all) {
          final players = all.where((r) => !r.entry.dropped).toList();
          final byId = {for (final r in players) r.player.id: r};
          final used = _used;
          final free = players.where((r) => !used.contains(r.player.id)).toList();
          final q = _query.toLowerCase();
          final shown = q.isEmpty
              ? free
              : free.where((r) => r.player.nickname.toLowerCase().contains(q)).toList();
          final odd = players.length.isOdd;
          final randomCount = free.length;
          String name(String id) => byId[id]?.player.nickname ?? '?';
          final tableCount = players.length ~/ 2;
          // Vista previa de las mesas de las parejas definidas (las al azar
          // ocupan luego las que queden libres).
          final real = [for (final p in _pairs) if (p.$2 != null) p];
          var preview = const <int>[];
          try {
            preview = SwissPairingEngine.assignTables(
              pairCount: tableCount,
              chosen: {
                for (var i = 0; i < real.length; i++)
                  if (_tables[real[i].$1] case final t?) i: t,
              },
            );
          } on TournamentException {
            preview = const [];
          }
          String tableLabel((String, String?) pair) {
            if (pair.$2 == null) return 'BYE';
            final i = real.indexOf(pair);
            return i >= 0 && i < preview.length ? 'Mesa ${preview[i]}' : 'Mesa ?';
          }

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Text(
                        'Toca un jugador y después su rival. Toca "Mesa" para elegir en qué '
                        'mesa juegan. Los que no tengan enfrentamiento definido se emparejan '
                        'al azar en las mesas que queden libres. Con el botón de pegar '
                        '(arriba) se importan los cruces desde un texto.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                    if (_pairs.isNotEmpty) ...[
                      SectionLabel('Definidos (${_pairs.length})'),
                      for (var i = 0; i < _pairs.length; i++)
                        _PairTile(
                          label: tableLabel(_pairs[i]),
                          chosen: _tables.containsKey(_pairs[i].$1),
                          a: name(_pairs[i].$1),
                          b: _pairs[i].$2 == null ? 'BYE' : name(_pairs[i].$2!),
                          onTable: _pairs[i].$2 == null
                              ? null
                              : () => _chooseTable(_pairs[i].$1, tableCount),
                          onRemove: () => setState(() {
                            _tables.remove(_pairs[i].$1);
                            _pairs.removeAt(i);
                          }),
                        ),
                    ],
                    SectionLabel('Sin definir (${free.length})'),
                    if (_selected != null)
                      NeonCard(
                        glow: true,
                        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('${name(_selected!)} vs … toca su rival',
                                  style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                            if (odd && !_hasBye)
                              TextButton(onPressed: _giveBye, child: const Text('Darle BYE')),
                            IconButton(
                              tooltip: 'Cancelar',
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() => _selected = null),
                            ),
                          ],
                        ),
                      ),
                    if (free.length > 8)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: TextField(
                          controller: _search,
                          decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search), hintText: 'Buscar jugador'),
                          onChanged: (v) => setState(() => _query = v.trim()),
                        ),
                      ),
                    for (final r in shown) _playerTile(r),
                    if (free.isEmpty)
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Todos los jugadores tienen enfrentamiento.',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _selected != null
                          ? null
                          : () => Navigator.pop(context, (pairs: _pairs, tables: _tables)),
                      child: Text(
                        '${widget.actionLabel} · ${_pairs.length} definido(s)'
                        '${randomCount > 0 ? ' · $randomCount al azar' : ''}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Elegir la mesa de una pareja: 1..[count]; las elegidas por otras
  /// parejas no se pueden usar. "Automática" deja que tome la libre más baja.
  Future<void> _chooseTable(String pairKey, int count) async {
    final taken = {
      for (final MapEntry(:key, :value) in _tables.entries)
        if (key != pairKey) value,
    };
    final current = _tables[pairKey];
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        actionsOverflowButtonSpacing: 10,
        title: const Text('Mesa'),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Automática'),
                selected: current == null,
                onSelected: (_) => Navigator.pop(ctx, 0),
              ),
              for (var t = 1; t <= count; t++)
                ChoiceChip(
                  label: Text('$t'),
                  selected: current == t,
                  onSelected: taken.contains(t) ? null : (_) => Navigator.pop(ctx, t),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (picked == 0) {
        _tables.remove(pairKey);
      } else {
        _tables[pairKey] = picked;
      }
    });
  }

  Widget _playerTile(RegisteredPlayer r) {
    final selected = _selected == r.player.id;
    return ListTile(
      selected: selected,
      selectedTileColor: AppColors.forest.withValues(alpha: 0.5),
      leading: DeckImage(path: r.deck?.imagePath, name: r.deck?.name ?? r.player.nickname, width: 36),
      title: Text(r.player.nickname,
          style: TextStyle(fontWeight: FontWeight.w700, color: selected ? AppColors.neon : null)),
      subtitle: Text(r.deck?.name ?? 'Sin mazo'),
      trailing: selected ? Icon(Icons.check_circle, color: AppColors.neon) : null,
      onTap: () => _tap(r.player.id),
    );
  }
}

class _PairTile extends StatelessWidget {
  const _PairTile({
    required this.label,
    required this.a,
    required this.b,
    required this.onRemove,
    this.onTable,
    this.chosen = false,
  });

  final String label;

  /// Elegir la mesa (null en el BYE).
  final VoidCallback? onTable;

  /// La mesa se eligió a mano.
  final bool chosen;
  final String a;
  final String b;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return NeonCard(
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
      child: Row(
        children: [
          InkWell(
            onTap: onTable,
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 86,
              child: Row(
                children: [
                  Flexible(
                    child: Text(label,
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: chosen ? AppColors.neonBright : AppColors.neon)),
                  ),
                  if (onTable != null)
                    Padding(
                      padding: EdgeInsets.only(left: 2),
                      child: Icon(Icons.edit, size: 14, color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: a, style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: '  vs  ', style: TextStyle(color: AppColors.textSecondary)),
                TextSpan(text: b, style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Quitar',
            icon: Icon(Icons.close, color: AppColors.textSecondary),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// Cuadro para pegar el texto de la ronda.
class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.initial});

  final String initial;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (clip?.text != null) setState(() => _text.text = clip!.text!);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      actionsOverflowButtonSpacing: 10,
      title: const Text('Importar ronda 1 desde texto'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Una mesa por línea, con los apodos de los inscritos:\n'
              'Mesa 1: Ana vs Luis\nMesa 2: José vs Mariela\nBYE: Pedro\n\n'
              'Sirve el texto de "Compartir ronda → Texto" (el título y los '
              'marcadores se ignoran).',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _text,
              minLines: 6,
              maxLines: 12,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: 'Pega aquí los cruces',
                alignLabelWithHint: true,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _paste,
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('Pegar del portapapeles'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _text.text),
          child: const Text('Importar'),
        ),
      ],
    );
  }
}
