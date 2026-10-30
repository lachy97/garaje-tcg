import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_paths.dart';
import '../domain/card_db.dart';

/// Dónde están publicadas las imágenes de las cartas: GitHub Pages del
/// repositorio público garaje-tcg-cartas (ver tools/cards/LEEME.md). Si se
/// añade otro servidor, se prueban en orden.
const cardImageHosts = <String>[
  'https://lachy97.github.io/garaje-tcg-cartas',
];

/// Carta usada para probar la descarga (Dark Magician).
const cardImageTestId = 46986414;

enum CardImageSize {
  /// Carta completa pequeña (≈ 168×246), para la cuadrícula de la lista.
  small('s'),

  /// Ilustración recortada, para la carta principal en grande.
  art('a');

  const CardImageSize(this.dir);
  final String dir;
}

/// Resultado de probar un servidor de imágenes.
class HostCheck {
  const HostCheck(this.host, {this.millis, this.bytes, this.error});
  final String host;
  final int? millis;
  final int? bytes;
  final String? error;
  bool get ok => error == null;
}

/// Descarga cada imagen la primera vez que se necesita y la guarda en
/// documentos/card_images/{s|a}/{código}.jpg; las siguientes veces se lee
/// del teléfono (sin datos móviles).
class CardImageStore {
  CardImageStore({
    required this.root,
    this.hosts = cardImageHosts,
    this.timeout = const Duration(seconds: 20),
  });

  final Directory root;
  final List<String> hosts;
  final Duration timeout;

  /// Índice del último servidor que funcionó (se prueba primero).
  int _preferred = 0;
  final _inflight = <String, Future<File?>>{};

  File fileFor(int id, CardImageSize size) => File('${root.path}/${size.dir}/$id.jpg');

  /// Archivo ya descargado, o null (sin red).
  File? cached(int id, CardImageSize size) {
    final f = fileFor(id, size);
    return f.existsSync() && f.lengthSync() > 0 ? f : null;
  }

  /// Imagen de la carta: la guardada o, si no está, la descarga. null si no
  /// hay conexión o ningún servidor la tiene.
  Future<File?> get(int id, CardImageSize size) {
    final hit = cached(id, size);
    if (hit != null) return Future.value(hit);
    final key = '${size.dir}/$id';
    // El callback no debe devolver el Future quitado del mapa: whenComplete
    // esperaría a ese Future, que es él mismo, y nunca terminaría.
    return _inflight[key] ??= _download(id, size).whenComplete(() {
      _inflight.remove(key);
    });
  }

  Future<File?> _download(int id, CardImageSize size) async {
    for (var k = 0; k < hosts.length; k++) {
      final i = (_preferred + k) % hosts.length;
      try {
        final bytes = await _fetch('${hosts[i]}/${size.dir}/$id.jpg');
        final file = fileFor(id, size);
        await file.parent.create(recursive: true);
        final tmp = File('${file.path}.part');
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(file.path);
        _preferred = i;
        return file;
      } catch (e) {
        debugPrint('Imagen $id (${size.dir}) no disponible en ${hosts[i]}: $e');
      }
    }
    return null;
  }

  /// Descarga una URL y comprueba que sea una imagen JPEG (no una página de
  /// error de un portal cautivo o de un proxy).
  Future<Uint8List> _fetch(String url) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw HttpException('HTTP ${res.statusCode}');
      }
      final bytes = await consolidateHttpClientResponseBytes(res).timeout(timeout * 3);
      if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
        throw const FormatException('la respuesta no es una imagen');
      }
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  /// Prueba cada servidor bajando la ilustración de [cardImageTestId] (sin
  /// guardarla): tiempo y tamaño, o el error.
  Future<List<HostCheck>> testHosts() async {
    final out = <HostCheck>[];
    for (final h in hosts) {
      final sw = Stopwatch()..start();
      try {
        final b = await _fetch('$h/${CardImageSize.art.dir}/$cardImageTestId.jpg');
        out.add(HostCheck(h, millis: sw.elapsedMilliseconds, bytes: b.length));
      } on TimeoutException {
        out.add(HostCheck(h, error: 'sin respuesta (tiempo agotado)'));
      } on SocketException catch (e) {
        out.add(HostCheck(h, error: 'sin conexión (${e.osError?.message ?? e.message})'));
      } catch (e) {
        out.add(HostCheck(h, error: '$e'));
      }
    }
    return out;
  }

  /// Espacio que ocupan las imágenes guardadas, en bytes, y cuántas son.
  Future<(int, int)> usage() async {
    if (!await root.exists()) return (0, 0);
    var total = 0, n = 0;
    await for (final e in root.list(recursive: true)) {
      if (e is File && e.path.endsWith('.jpg')) {
        total += await e.length();
        n++;
      }
    }
    return (total, n);
  }

  /// Borra las imágenes guardadas (se volverán a bajar cuando hagan falta).
  Future<void> clear() async {
    if (await root.exists()) await root.delete(recursive: true);
  }
}

final cardImageStoreProvider = Provider<CardImageStore>((ref) {
  final docs = AppPaths.documents ?? Directory.systemTemp.path;
  return CardImageStore(root: Directory('$docs/card_images'));
});

CardDb _parseCardDb(String source) => CardDb.fromJsonString(source);

/// Base de cartas de Edison empaquetada en la app (vacía hasta que se genere
/// con el workflow "Cartas Edison").
final cardDbProvider = FutureProvider<CardDb>((ref) async {
  final source = await rootBundle.loadString('assets/cards/edison_cards.json');
  return compute(_parseCardDb, source);
});
