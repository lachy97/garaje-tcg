import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/features/decklists/data/card_images.dart';
import 'package:garaje_tcg/features/decklists/domain/card_db.dart';

const _json = '''
{"version":"2026-10-18","count":8,"cards":[
 {"i":46986414,"n":"Dark Magician","f":"normal","l":3,"a":[38033121]},
 {"i":40044918,"n":"Elemental HERO Stratos","f":"effect","l":1},
 {"i":24094653,"n":"Polymerization","f":"spell","l":3},
 {"i":57728570,"n":"Crush Card Virus","f":"trap","l":0},
 {"i":75180828,"n":"Gravekeeper's Spy","f":"effect"},
 {"i":40737112,"n":"Dark Magician of Chaos","f":"effect","l":1},
 {"i":2129638,"n":"Blue-Eyes Ultimate Dragon","f":"fusion","l":3},
 {"i":90011152,"n":"Stardust Dragon","f":"synchro","l":3}
]}
''';

void main() {
  final db = CardDb.fromJsonString(_json);

  test('lee el JSON compacto', () {
    expect(db.length, 8);
    expect(db.version, '2026-10-18');
    expect(db.byId(57728570)!.limit, 0);
    expect(db.byId(75180828)!.limit, 3, reason: 'sin "l" = 3 copias');
  });

  test('busca por código, también ilustraciones alternativas', () {
    expect(db.byId(46986414)!.name, 'Dark Magician');
    expect(db.byId(38033121)!.id, 46986414);
    expect(db.byId(1), isNull);
  });

  test('busca por nombre sin importar mayúsculas, signos ni tildes', () {
    expect(db.byName('gravekeepers spy')!.id, 75180828);
    expect(db.byName('GRAVEKEEPER’S SPY')!.id, 75180828);
    expect(db.byName('Elemental Hero Strátos')!.id, 40044918);
    expect(db.byName('Blue Eyes Ultimate Dragon')!.id, 2129638);
    expect(db.byName('Dark Magician of'), isNull);
    expect(db.byName('  '), isNull);
  });

  test('normalize', () {
    expect(CardDb.normalize('D.D. Warrior Lady'), 'ddwarriorlady');
    expect(CardDb.normalize('Ñandú 2'), 'nandu2');
  });

  test('grupo de cada carta', () {
    expect(db.byName('Polymerization')!.group, CardGroup.spell);
    expect(db.byName('Crush Card Virus')!.group, CardGroup.trap);
    expect(db.byName('Stardust Dragon')!.group, CardGroup.extra);
    expect(db.byName('Blue-Eyes Ultimate Dragon')!.isExtra, isTrue);
    expect(db.byName('Dark Magician')!.group, CardGroup.monster);
  });

  test('buscador: exacto, luego prefijo, luego contiene', () {
    final r = db.search('dark magician');
    expect(r.map((c) => c.name), ['Dark Magician', 'Dark Magician of Chaos']);
    expect(db.search('dragon').map((c) => c.name),
        ['Blue-Eyes Ultimate Dragon', 'Stardust Dragon']);
    expect(db.search('chaos magician').single.name, 'Dark Magician of Chaos');
    expect(db.search(''), isEmpty);
    expect(db.search('dragon', limit: 1), hasLength(1));
  });

  test('el marcador de posición del asset es una base vacía válida', () {
    final placeholder = File('assets/cards/edison_cards.json').readAsStringSync();
    final d = CardDb.fromJsonString(placeholder);
    expect(jsonDecode(placeholder), isA<Map>());
    if (d.isEmpty) expect(d.version, isEmpty);
  });

  group('CardImageStore', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('cards'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('usa la imagen guardada sin red', () async {
      // root en una subcarpeta: clear() la borra y tearDown borra tmp.
      final store = CardImageStore(root: Directory('${tmp.path}/imgs'), hosts: const []);
      final f = store.fileFor(46986414, CardImageSize.small);
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
      expect((await store.get(46986414, CardImageSize.small))!.path, f.path);
      expect(await store.get(46986414, CardImageSize.art), isNull,
          reason: 'sin servidores y sin archivo');
      final (bytes, n) = await store.usage();
      expect((bytes, n), (4, 1));
      await store.clear();
      expect(store.cached(46986414, CardImageSize.small), isNull);
    });

    test('descarga de un servidor local y rechaza lo que no es JPEG', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        final path = req.uri.path;
        if (path == '/a/1.jpg') {
          req.response.add([0xFF, 0xD8, 1, 2, 3]);
        } else if (path == '/a/2.jpg') {
          req.response.write('<html>portal cautivo</html>');
        } else {
          req.response.statusCode = 404;
        }
        req.response.close();
      });
      final host = 'http://${server.address.host}:${server.port}';
      final store = CardImageStore(root: tmp, hosts: ['http://127.0.0.1:1', host]);
      final f = await store.get(1, CardImageSize.art);
      expect(f, isNotNull);
      expect(f!.readAsBytesSync(), [0xFF, 0xD8, 1, 2, 3]);
      expect(await store.get(2, CardImageSize.art), isNull);
      expect(await store.get(3, CardImageSize.art), isNull);
      expect(store.fileFor(2, CardImageSize.art).existsSync(), isFalse);
      final checks = await CardImageStore(root: tmp, hosts: [host]).testHosts();
      expect(checks.single.ok, isFalse, reason: 'el servidor de prueba no tiene la carta de test');
      await server.close(force: true);
    });
  });
}
