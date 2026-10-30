import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../app/widgets/brand.dart';
import '../../../../app/widgets/common.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/db/daos/tournaments_dao.dart';
import '../../../decks/presentation/deck_image.dart';
import '../providers.dart';

/// Ronda 1 con enfrentamientos definidos por el organizador: se toca un
/// jugador y luego su rival (o "BYE" si el número es impar). Los que queden
/// sin definir se emparejan al azar. Devuelve las parejas (rival null = BYE)
/// o null si se cancela.
class FirstRoundPairingPage extends ConsumerStatefulWidget {
  const FirstRoundPairingPage({super.key, required this.tournament});

  final Tournament tournament;

  @override
  ConsumerState<FirstRoundPairingPage> createState() => _FirstRoundPairingPageState();
}

class _FirstRoundPairingPageState extends ConsumerState<FirstRoundPairingPage> {
  final _pairs = <(String, String?)>[];
  String? _selected;
  String _query = '';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
      appBar: AppBar(title: const Text('CRUCES DE LA RONDA 1')),
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

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Text(
                        'Toca un jugador y después su rival. Los que no tengan '
                        'enfrentamiento definido se emparejan al azar al generar la ronda.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                    if (_pairs.isNotEmpty) ...[
                      SectionLabel('Definidos (${_pairs.length})'),
                      for (var i = 0; i < _pairs.length; i++)
                        _PairTile(
                          label: _pairs[i].$2 == null ? 'BYE' : 'Mesa ${_tableOf(i)}',
                          a: name(_pairs[i].$1),
                          b: _pairs[i].$2 == null ? 'BYE' : name(_pairs[i].$2!),
                          onRemove: () => setState(() => _pairs.removeAt(i)),
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
                      const Padding(
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
                      onPressed: _selected != null ? null : () => Navigator.pop(context, _pairs),
                      child: Text(
                        'GENERAR RONDA 1 · ${_pairs.length} definido(s)'
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

  /// Número de mesa de la pareja i (las del BYE no cuentan).
  int _tableOf(int i) {
    var n = 0;
    for (var k = 0; k <= i; k++) {
      if (_pairs[k].$2 != null) n++;
    }
    return n;
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
      trailing: selected ? const Icon(Icons.check_circle, color: AppColors.neon) : null,
      onTap: () => _tap(r.player.id),
    );
  }
}

class _PairTile extends StatelessWidget {
  const _PairTile({required this.label, required this.a, required this.b, required this.onRemove});

  final String label;
  final String a;
  final String b;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return NeonCard(
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.neon)),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: a, style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: '  vs  ', style: TextStyle(color: AppColors.textSecondary)),
                TextSpan(text: b, style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Quitar',
            icon: const Icon(Icons.close, color: AppColors.textSecondary),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
