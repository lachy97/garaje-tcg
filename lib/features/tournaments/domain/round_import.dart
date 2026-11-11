/// Importar los cruces de la ronda 1 desde texto (p. ej. el que se compartió
/// por WhatsApp con "Compartir ronda → Texto", o una lista escrita a mano).
/// Dart puro.
///
/// Líneas que entiende (una por mesa; mayúsculas, tildes y asteriscos de
/// WhatsApp dan igual):
///
///   Mesa 3: Ana vs Luis        3. Ana vs Luis        Ana vs Luis
///   Mesa 3: Ana 2-1 Luis       (el marcador se ignora: solo cuentan los cruces)
///   BYE: Pedro                 Pedro BYE             Pedro vs BYE
///
/// El resto de líneas (título, "Faltan 2 resultado(s)", vacías) se ignoran.
library;

/// Un jugador al que se puede emparejar.
class ImportCandidate {
  const ImportCandidate({required this.id, required this.nickname, this.fullName});

  final String id;
  final String nickname;
  final String? fullName;
}

class RoundImportResult {
  const RoundImportResult({
    required this.pairs,
    required this.tables,
    required this.problems,
  });

  /// Parejas (rival null = BYE).
  final List<(String, String?)> pairs;

  /// Mesa indicada en el texto, por el primer jugador de la pareja.
  final Map<String, int> tables;

  /// Avisos legibles (nombres no encontrados, repetidos, mesas inválidas…).
  final List<String> problems;
}

/// Quita tildes, asteriscos y espacios de más, y pasa a minúsculas.
String normalizeName(String s) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b
      .toString()
      .replaceAll(RegExp(r'[*_~`]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

final _tablePrefix = RegExp(
  r'^(?:(?:mesa|match|m|table)\s*#?\s*(\d+)|#?(\d+))\s*[:.)\-–]\s*',
  caseSensitive: false,
);

/// Lo que va entre los dos jugadores: "vs", un marcador o un resultado.
final _middle = RegExp(
  r'\s+(?:vs\.?|v\.?|contra|\d+\s*-\s*\d+(?:\s*-\s*\d+)?|empate(?:\s+\d+-\d+-\d+)?|id|doble derrota)\s+',
  caseSensitive: false,
);

final _byeFirst = RegExp(r'^bye(?:\s*[:\-–]\s*|\s+)(.+)$', caseSensitive: false);
final _byeLast =
    RegExp(r'^(.+?)\s*(?:[:\-–]|vs\.?)?\s*\(?(?<![a-z0-9])bye\)?$', caseSensitive: false);

RoundImportResult parseRoundText(String text, List<ImportCandidate> players) {
  // Índices de búsqueda: apodo y nombre completo normalizados.
  final byNick = <String, List<ImportCandidate>>{};
  final byFull = <String, List<ImportCandidate>>{};
  for (final p in players) {
    (byNick[normalizeName(p.nickname)] ??= []).add(p);
    final f = p.fullName;
    if (f != null && f.trim().isNotEmpty) (byFull[normalizeName(f)] ??= []).add(p);
  }

  final problems = <String>[];
  final notFound = <String>[];

  ImportCandidate? find(String raw) {
    final n = normalizeName(raw);
    if (n.isEmpty) return null;
    for (final index in [byNick, byFull]) {
      final hit = index[n];
      if (hit != null && hit.length == 1) return hit.first;
      if (hit != null && hit.length > 1) {
        problems.add('"$raw": hay ${hit.length} jugadores con ese nombre.');
        return null;
      }
    }
    // Último intento: un único apodo que contenga el texto (o al revés).
    final partial = [
      for (final p in players)
        if (n.length >= 3 &&
            (normalizeName(p.nickname).contains(n) || n.contains(normalizeName(p.nickname))))
          p,
    ];
    if (partial.length == 1) {
      problems.add('"${raw.trim()}" se tomó como ${partial.first.nickname}: revísalo.');
      return partial.first;
    }
    notFound.add(raw.trim());
    return null;
  }

  final pairs = <(String, String?)>[];
  final tables = <String, int>{};
  final used = <String>{};
  final usedTables = <int>{};

  bool take(ImportCandidate p) {
    if (used.add(p.id)) return true;
    problems.add('${p.nickname} aparece más de una vez (se usa la primera).');
    return false;
  }

  for (final rawLine in text.split(RegExp(r'\r?\n'))) {
    var line = rawLine.replaceAll(RegExp(r'[*_~`]'), '').trim();
    // Vacías y el título del texto compartido ("Torneo · Ronda 1").
    if (line.isEmpty || line.contains(' · ')) continue;

    int? table;
    final tm = _tablePrefix.firstMatch(line);
    if (tm != null) {
      table = int.tryParse(tm.group(1) ?? tm.group(2) ?? '');
      line = line.substring(tm.end).trim();
    }

    // BYE
    final bf = _byeFirst.firstMatch(line);
    final bl = bf == null ? _byeLast.firstMatch(line) : null;
    final byeName = bf?.group(1) ?? bl?.group(1);
    if (byeName != null && byeName.trim().isNotEmpty) {
      final p = find(byeName);
      if (p == null) continue;
      if (pairs.any((x) => x.$2 == null)) {
        problems.add('Más de un BYE: ${p.nickname} queda sin definir.');
        continue;
      }
      if (take(p)) pairs.add((p.id, null));
      continue;
    }

    // Jugador vs jugador
    final mm = _middle.firstMatch(line);
    if (mm == null) continue; // título u otra línea
    final a = find(line.substring(0, mm.start));
    final b = find(line.substring(mm.end));
    if (a == null || b == null) continue;
    if (a.id == b.id) {
      problems.add('${a.nickname} aparece contra sí mismo.');
      continue;
    }
    if (used.contains(a.id) || used.contains(b.id)) {
      final dup = used.contains(a.id) ? a : b;
      problems.add('${dup.nickname} aparece más de una vez (se usa la primera).');
      continue;
    }
    take(a);
    take(b);
    pairs.add((a.id, b.id));
    if (table != null) {
      if (usedTables.add(table)) {
        tables[a.id] = table;
      } else {
        problems.add('Mesa $table repetida: ${a.nickname} vs ${b.nickname} toma otra libre.');
      }
    }
  }

  if (notFound.isNotEmpty) {
    problems.insert(0, 'No inscritos o no encontrados: ${notFound.join(', ')}.');
  }
  return RoundImportResult(pairs: pairs, tables: tables, problems: problems);
}
