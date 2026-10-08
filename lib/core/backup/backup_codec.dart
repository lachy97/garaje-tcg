import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Formato de las copias de seguridad (.gtcg). Dart puro, testeable.
///
///   "GTCGBAK1"            8 bytes, identifica el archivo
///   largo de cabecera     4 bytes (big-endian)
///   cabecera JSON         fecha, versión de la BD, cantidades
///   BD SQLite comprimida  gzip
///   sello HMAC-SHA256     32 bytes sobre todo lo anterior
///
/// El sello se calcula con una clave interna de la app: solo se aceptan
/// copias hechas por Garage TCG (de cualquier teléfono) y se detecta si el
/// archivo se dañó al enviarlo.
class BackupCodec {
  const BackupCodec._();

  static const extension = 'gtcg';
  static final _magic = ascii.encode('GTCGBAK1');
  static const _macLength = 32;
  static final _sqliteMagic = ascii.encode('SQLite format 3\u0000');
  static final _hmac = Hmac(sha256, const [
    0xf0, 0x9b, 0x7a, 0xa3, 0x94, 0x0c, 0x61, 0x42, 0xaf, 0x78, 0x1d, 0xfa, 0x7a, 0xc7, 0x7b, 0x30, //
    0x6d, 0xf7, 0x1d, 0x8e, 0x00, 0x6b, 0xc3, 0x6a, 0x3f, 0x07, 0x10, 0x3c, 0x33, 0x41, 0x62, 0x01,
  ]);

  static Uint8List encode(BackupHeader header, Uint8List sqlite) {
    final headerBytes = utf8.encode(jsonEncode(header.toJson()));
    final body = BytesBuilder(copy: false)
      ..add(_magic)
      ..add(_u32(headerBytes.length))
      ..add(headerBytes)
      ..add(gzip.encode(sqlite));
    final content = body.toBytes();
    final mac = _hmac.convert(content).bytes;
    return Uint8List.fromList([...content, ...mac]);
  }

  /// Lee y valida una copia. Lanza [BackupException] si no es de la app,
  /// está dañada o no contiene una base de datos.
  static (BackupHeader, Uint8List) decode(Uint8List file) {
    const notOurs = BackupException(
        'Este archivo no es una copia de seguridad de Garage TCG.');
    if (file.length < _magic.length + 4 + _macLength) throw notOurs;
    for (var i = 0; i < _magic.length; i++) {
      if (file[i] != _magic[i]) throw notOurs;
    }
    final content = Uint8List.sublistView(file, 0, file.length - _macLength);
    final mac = Uint8List.sublistView(file, file.length - _macLength);
    if (!_equals(_hmac.convert(content).bytes, mac)) {
      throw const BackupException(
          'El archivo está dañado o fue modificado. Pide que lo exporten de nuevo.');
    }
    final headerLen = ByteData.sublistView(content, 8, 12).getUint32(0);
    if (12 + headerLen > content.length) throw notOurs;
    final BackupHeader header;
    final Uint8List sqlite;
    try {
      header = BackupHeader.fromJson(
          jsonDecode(utf8.decode(content.sublist(12, 12 + headerLen))) as Map<String, dynamic>);
      sqlite = Uint8List.fromList(gzip.decode(content.sublist(12 + headerLen)));
    } on Object {
      throw notOurs;
    }
    if (sqlite.length < 100) throw notOurs;
    for (var i = 0; i < _sqliteMagic.length; i++) {
      if (sqlite[i] != _sqliteMagic[i]) throw notOurs;
    }
    return (header, sqlite);
  }

  /// Versión del esquema guardada por Drift en la cabecera SQLite (user_version).
  static int sqliteUserVersion(Uint8List sqlite) => ByteData.sublistView(sqlite, 60, 64).getUint32(0);

  static List<int> _u32(int v) => [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255];

  static bool _equals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

class BackupHeader {
  const BackupHeader({
    required this.exportedAt,
    required this.schemaVersion,
    this.players = 0,
    this.tournaments = 0,
    this.decks = 0,
  });

  factory BackupHeader.fromJson(Map<String, dynamic> j) => BackupHeader(
        exportedAt: DateTime.parse(j['exportedAt'] as String),
        schemaVersion: j['schema'] as int,
        players: j['players'] as int? ?? 0,
        tournaments: j['tournaments'] as int? ?? 0,
        decks: j['decks'] as int? ?? 0,
      );

  final DateTime exportedAt;
  final int schemaVersion;
  final int players;
  final int tournaments;
  final int decks;

  Map<String, dynamic> toJson() => {
        'app': 'garage_tcg',
        'format': 1,
        'exportedAt': exportedAt.toIso8601String(),
        'schema': schemaVersion,
        'players': players,
        'tournaments': tournaments,
        'decks': decks,
      };
}

class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}
