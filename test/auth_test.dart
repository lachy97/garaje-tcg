import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/auth/account.dart';
import 'package:garaje_tcg/core/auth/auth_api.dart';
import 'package:garaje_tcg/core/auth/auth_rules.dart';
import 'package:garaje_tcg/core/auth/local_auth_api.dart';
import 'package:garaje_tcg/core/auth/permissions.dart';

void main() {
  group('AuthRules', () {
    test('usuario', () {
      expect(AuthRules.validateUsername('Lachy_97'), isNull);
      expect(AuthRules.normalizeUsername('  Lachy_97 '), 'lachy_97');
      expect(AuthRules.validateUsername('ab'), isNotNull);
      expect(AuthRules.validateUsername('con espacio'), isNotNull);
      expect(AuthRules.validateUsername('niño'), isNotNull);
    });

    test('solo Gmail', () {
      expect(AuthRules.validateEmail('Lachy@Gmail.com'), isNull);
      expect(AuthRules.normalizeEmail(' Lachy@GoogleMail.com '), 'lachy@gmail.com');
      expect(AuthRules.validateEmail('lachy@nauta.cu'), isNotNull);
      expect(AuthRules.validateEmail(''), isNotNull);
    });

    test('contraseña, teléfono y código', () {
      expect(AuthRules.validatePassword('abc12345'), isNull);
      expect(AuthRules.validatePassword('abcdefgh'), isNotNull);
      expect(AuthRules.validatePassword('a1'), isNotNull);
      expect(AuthRules.validatePhone(''), isNull);
      expect(AuthRules.validatePhone('+53 5123 4567'), isNull);
      expect(AuthRules.validatePhone('abc'), isNotNull);
      expect(AuthRules.validateCode('123456'), isNull);
      expect(AuthRules.validateCode('12345'), isNotNull);
    });
  });

  group('LocalAuthApi', () {
    late DateTime now;
    late List<String> codes;
    late LocalAuthApi api;
    var admin = true;

    setUp(() {
      now = DateTime(2026, 11, 9, 10);
      codes = ['111111', '222222', '333333', '444444', '555555', '666666'];
      admin = true;
      api = LocalAuthApi(
        MemoryAuthStore(),
        now: () => now,
        newCode: () => codes.removeAt(0),
        isAdminDevice: () async => admin,
        hashIterations: 10,
      );
    });

    Future<Session> registerAndVerify(String user, String email) async {
      await api.register(username: user, email: email, password: 'clave1234', nickname: user);
      final code = (await api.outbox()).first.code;
      return api.verifyEmail(email: email, code: code);
    }

    test('registro, verificación y login con usuario o Gmail', () async {
      await api.register(
          username: 'Lachy', email: 'lachy@gmail.com', password: 'clave1234', nickname: 'Lachy');
      // Sin verificar no puede entrar.
      await expectLater(api.login(identifier: 'lachy', password: 'clave1234'),
          throwsA(isA<UnverifiedAccountException>()));
      final sent = (await api.outbox()).first;
      expect(sent.to, 'lachy@gmail.com');
      expect(sent.code, '111111');

      final s = await api.verifyEmail(email: 'lachy@gmail.com', code: '111111');
      expect(s.account.verified, isTrue);
      // Primera cuenta en el teléfono del administrador → Administrador.
      expect(s.account.role, AppRole.admin);
      expect(s.expiresAt, now.add(const Duration(days: 30)));

      final byUser = await api.login(identifier: 'LACHY', password: 'clave1234');
      expect(byUser.account.username, 'lachy');
      final byMail = await api.login(identifier: 'Lachy@gmail.com', password: 'clave1234');
      expect(byMail.account.id, byUser.account.id);
      await expectLater(api.login(identifier: 'lachy', password: 'otra12345'), throwsA(isA<AuthException>()));
    });

    test('usuario y Gmail únicos; las demás cuentas son Jugador', () async {
      await registerAndVerify('lachy', 'lachy@gmail.com');
      now = now.add(const Duration(minutes: 2));
      await expectLater(
          api.register(username: 'LACHY', email: 'otro@gmail.com', password: 'clave1234', nickname: 'x'),
          throwsA(isA<AuthException>()));
      await expectLater(
          api.register(username: 'otro', email: 'LACHY@gmail.com', password: 'clave1234', nickname: 'x'),
          throwsA(isA<AuthException>()));
      final s = await registerAndVerify('leo', 'leo@gmail.com');
      expect(s.account.role, AppRole.player);
    });

    test('código: 5 intentos, vence a los 15 min, 3 por hora', () async {
      admin = false;
      await api.register(username: 'leo', email: 'leo@gmail.com', password: 'clave1234', nickname: 'Leo');
      for (var i = 0; i < 4; i++) {
        await expectLater(api.verifyEmail(email: 'leo@gmail.com', code: '000000'),
            throwsA(isA<AuthException>()));
      }
      // El 5º fallo consume el código: ya no sirve ni el bueno.
      await expectLater(api.verifyEmail(email: 'leo@gmail.com', code: '000000'),
          throwsA(isA<AuthException>()));
      await expectLater(api.verifyEmail(email: 'leo@gmail.com', code: '111111'),
          throwsA(isA<AuthException>()));

      // Reenviar: hay que esperar 60 s.
      await expectLater(api.resendVerification('leo@gmail.com'), throwsA(isA<AuthException>()));
      now = now.add(const Duration(seconds: 61));
      await api.resendVerification('leo@gmail.com'); // 222222
      now = now.add(const Duration(minutes: 16));
      await expectLater(api.verifyEmail(email: 'leo@gmail.com', code: '222222'),
          throwsA(isA<AuthException>()));

      await api.resendVerification('leo@gmail.com'); // 333333 (3º de la hora)
      now = now.add(const Duration(seconds: 61));
      await expectLater(api.resendVerification('leo@gmail.com'), throwsA(isA<AuthException>()));
      final s = await api.verifyEmail(email: 'leo@gmail.com', code: '333333');
      expect(s.account.verified, isTrue);
    });

    test('olvido de contraseña con código', () async {
      final old = await registerAndVerify('lachy', 'lachy@gmail.com');
      now = now.add(const Duration(minutes: 2));
      final mail = await api.requestPasswordReset('lachy');
      expect(mail, 'lachy@gmail.com');
      final code = (await api.outbox()).first.code;
      expect((await api.outbox()).first.purpose, 'reset');
      await api.resetPassword(identifier: 'lachy', code: code, newPassword: 'nueva9876');
      await expectLater(api.login(identifier: 'lachy', password: 'clave1234'), throwsA(isA<AuthException>()));
      expect((await api.login(identifier: 'lachy', password: 'nueva9876')).account.username, 'lachy');
      // Las sesiones anteriores quedan cerradas.
      await expectLater(api.me(old), throwsA(isA<AuthException>()));
    });

    test('administrador: roles, vincular ficha, verificar a mano', () async {
      final adminS = await registerAndVerify('lachy', 'lachy@gmail.com');
      now = now.add(const Duration(minutes: 2));
      await api.register(username: 'leo', email: 'leo@gmail.com', password: 'clave1234', nickname: 'Leo');
      final accounts = await api.listAccounts(adminS);
      final leo = accounts.firstWhere((a) => a.username == 'leo');
      expect(leo.verified, isFalse);

      await api.verifyManually(adminS, accountId: leo.id);
      final org = await api.setRole(adminS, accountId: leo.id, role: AppRole.organizer);
      expect(org.role, AppRole.organizer);
      final linked = await api.linkPlayer(adminS, accountId: leo.id, playerId: 'p1');
      expect(linked.playerId, 'p1');
      // Una ficha solo puede tener una cuenta.
      await expectLater(api.linkPlayer(adminS, accountId: adminS.account.id, playerId: 'p1'),
          throwsA(isA<AuthException>()));
      // No puede quitarse el rol a sí mismo.
      await expectLater(api.setRole(adminS, accountId: adminS.account.id, role: AppRole.player),
          throwsA(isA<AuthException>()));

      // Un jugador no puede usar las funciones de administrador.
      final leoS = await api.login(identifier: 'leo', password: 'clave1234');
      await expectLater(api.listAccounts(leoS), throwsA(isA<AuthException>()));
      expect((await api.me(leoS)).playerId, 'p1');
    });

    test('la sesión vence a los 30 días', () async {
      final s = await registerAndVerify('lachy', 'lachy@gmail.com');
      now = now.add(const Duration(days: 31));
      expect(s.isExpired(now), isTrue);
      await expectLater(api.me(s), throwsA(isA<AuthException>()));
    });
  });

  group('Permissions', () {
    test('modo local: todo permitido', () {
      const p = Permissions.local();
      expect(p.canSeeAllPlayers, isTrue);
      expect(p.canCreateTournaments, isTrue);
      expect(p.canSeePlayerProfile('x'), isTrue);
      expect(p.canManageAccounts, isFalse); // sin cuenta no hay cuentas que gestionar
    });

    test('jugador sin licencia: lo suyo gratis', () {
      const p = Permissions(role: AppRole.player, hasLicense: false, playerId: 'me');
      expect(p.canSeeRanking && p.canSeeTierList, isTrue);
      expect(p.canSeePlayerProfile('me'), isTrue);
      expect(p.canSeePlayerProfile('otro'), isFalse);
      expect(p.canSeeAllPlayers, isFalse);
      expect(p.canSeeDeckStats, isFalse);
      expect(p.canSeeTournament(isEnrolled: true), isTrue);
      expect(p.canSeeTournament(), isFalse);
      expect(p.canCreateTournaments, isFalse);
      expect(p.canBackup, isFalse);
    });

    test('jugador con licencia: estadísticas de mazos, no fichas ajenas', () {
      const p = Permissions(role: AppRole.player, hasLicense: true, playerId: 'me');
      expect(p.canSeeDeckStats, isTrue);
      expect(p.canSeePlayerProfile('otro'), isFalse);
      expect(p.canCreateTournaments, isFalse);
    });

    test('organizador necesita licencia; juez usa la del torneo', () {
      const sin = Permissions(role: AppRole.organizer, hasLicense: false);
      expect(sin.canCreateTournaments, isFalse);
      expect(sin.canManageTournament(isOwner: true), isFalse);
      const con = Permissions(role: AppRole.organizer, hasLicense: true);
      expect(con.canCreateTournaments, isTrue);
      expect(con.canManageTournament(isOwner: true), isTrue);
      expect(con.canManageTournament(isOwner: false), isFalse);
      expect(con.canSeeAllPlayers, isFalse);

      const juez = Permissions(role: AppRole.judge, hasLicense: false);
      expect(juez.canReportResults(isOwner: false, isJudge: true), isTrue);
      expect(juez.canReportResults(isOwner: false), isFalse);
      expect(juez.canManageTournament(isOwner: false), isFalse);
    });

    test('administrador con cuenta', () {
      const p = Permissions(role: AppRole.admin, hasLicense: false);
      expect(p.canSeeAllPlayers && p.canManageAccounts && p.canSeeDeckStats, isTrue);
    });
  });
}
