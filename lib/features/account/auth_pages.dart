import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/widgets/brand.dart';
import '../../app/widgets/common.dart';
import '../../core/auth/account.dart';
import '../../core/auth/auth_api.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/auth/auth_rules.dart';

/// Ejecuta una acción de cuentas mostrando el error tal cual.
/// Devuelve true si salió bien.
Future<bool> _guard(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } on AuthException catch (e) {
    if (context.mounted) showMessage(context, e.message, error: true);
  } catch (e) {
    if (context.mounted) showMessage(context, 'No se pudo conectar: $e', error: true);
  }
  return false;
}

/// Abre una pantalla de cuentas.
Future<T?> openAuthPage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

/// Marco común: logo, título y formulario centrado.
class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.title, required this.children, this.busy = false});

  final String title;
  final List<Widget> children;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              const Center(child: GlowLogo(size: 72)),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
          if (busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x88000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

/// Aviso de la simulación: los correos no se envían, el código se ve aquí.
class SimulatedMailBox extends ConsumerStatefulWidget {
  const SimulatedMailBox({super.key, required this.email, required this.purpose, this.refresh = 0});

  final String email;
  final String purpose;

  /// Cambiarlo vuelve a leer el último código (tras "Reenviar").
  final int refresh;

  @override
  ConsumerState<SimulatedMailBox> createState() => _SimulatedMailBoxState();
}

class _SimulatedMailBoxState extends ConsumerState<SimulatedMailBox> {
  late Future<List<SentEmail>> _mails;

  @override
  void initState() {
    super.initState();
    _mails = ref.read(authApiProvider).outbox();
  }

  @override
  void didUpdateWidget(SimulatedMailBox old) {
    super.didUpdateWidget(old);
    if (old.refresh != widget.refresh || old.email != widget.email) {
      _mails = ref.read(authApiProvider).outbox();
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(authApiProvider);
    final email = AuthRules.normalizeEmail(widget.email);
    return FutureBuilder<List<SentEmail>>(
      future: _mails,
      builder: (context, snap) {
        final mail = snap.data
            ?.where((m) => m.to == email && m.purpose == widget.purpose)
            .firstOrNull;
        // Servidor real sin modo de pruebas: el código llega solo al correo.
        if (!api.isSimulated && mail == null) return const SizedBox.shrink();
        final who = api.isSimulated ? 'Servidor de prueba' : 'Servidor en modo de pruebas';
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.draw.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.draw),
          ),
          child: Row(
            children: [
              const Icon(Icons.science_outlined, color: AppColors.draw),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  mail == null
                      ? '$who: los correos todavía no se envían. '
                          'Pide un código y aparecerá aquí.'
                      : '$who: los correos todavía no se envían. '
                          'Tu código es ${mail.code}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (mail != null)
                IconButton(
                  tooltip: 'Copiar código',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () => Clipboard.setData(ClipboardData(text: mail.code)),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ───────────────────────── Iniciar sesión ─────────────────────────

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _show = false;

  @override
  void dispose() {
    _id.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).login(_id.text, _pass.text);
      if (mounted) Navigator.of(context).pop(true);
    } on UnverifiedAccountException catch (e) {
      if (!mounted) return;
      showMessage(context, e.message);
      final ok = await openAuthPage<bool>(context, VerifyEmailPage(email: e.email));
      if ((ok ?? false) && mounted) Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) showMessage(context, 'No se pudo conectar: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'INICIAR SESIÓN',
      busy: _busy,
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _id,
                autofillHints: const [AutofillHints.username, AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Usuario o Gmail',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Escribe tu usuario o Gmail' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pass,
                obscureText: !_show,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _show = !_show),
                  ),
                ),
                validator: (v) => (v ?? '').isEmpty ? 'Escribe tu contraseña' : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _busy ? null : _submit, child: const Text('Entrar')),
              TextButton(
                onPressed: () => openAuthPage<void>(
                    context, ResetPasswordPage(initialIdentifier: _id.text.trim())),
                child: const Text('Olvidé mi contraseña'),
              ),
              const Divider(height: 32),
              OutlinedButton(
                onPressed: () async {
                  final ok = await openAuthPage<bool>(context, const RegisterPage());
                  if ((ok ?? false) && context.mounted) Navigator.of(context).pop(true);
                },
                child: const Text('Crear cuenta'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── Crear cuenta ─────────────────────────

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _form = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _email = TextEditingController();
  final _nick = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _busy = false;
  bool _show = false;

  @override
  void dispose() {
    for (final c in [_user, _email, _nick, _phone, _pass, _pass2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    var go = false;
    try {
      await ref.read(authApiProvider).register(
            username: _user.text,
            email: _email.text,
            password: _pass.text,
            nickname: _nick.text,
            phone: _phone.text,
          );
      go = true;
    } on UnverifiedAccountException {
      // Ya se había registrado sin confirmar: se pasa a poner el código.
      go = true;
    } on AuthException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) showMessage(context, 'No se pudo conectar: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!go || !mounted) return;
    final ok = await openAuthPage<bool>(context, VerifyEmailPage(email: _email.text));
    if ((ok ?? false) && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'CREAR CUENTA',
      busy: _busy,
      children: [
        const Text(
          'Con tu cuenta podrás preinscribirte en los torneos y ver tu ficha. '
          'Te enviaremos un código a tu Gmail para confirmarla.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 16),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _user,
                decoration: const InputDecoration(
                  labelText: 'Usuario',
                  helperText: 'Único. Letras, números, punto o guion bajo',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
                validator: (v) => AuthRules.validateUsername(v ?? ''),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Gmail',
                  hintText: 'tunombre@gmail.com',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
                validator: (v) => AuthRules.validateEmail(v ?? ''),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nick,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Apodo',
                  helperText: 'Como te conocen en los torneos',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (v) => AuthRules.validateNickname(v ?? ''),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono (opcional)',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (v) => AuthRules.validatePhone(v ?? ''),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pass,
                obscureText: !_show,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  helperText: 'Al menos 8 caracteres, con letras y números',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _show = !_show),
                  ),
                ),
                validator: (v) => AuthRules.validatePassword(v ?? ''),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pass2,
                obscureText: !_show,
                decoration: const InputDecoration(
                  labelText: 'Repite la contraseña',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (v) => v != _pass.text ? 'Las contraseñas no coinciden' : null,
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _busy ? null : _submit, child: const Text('Crear cuenta')),
            ],
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── Confirmar Gmail ─────────────────────────

class VerifyEmailPage extends ConsumerStatefulWidget {
  const VerifyEmailPage({super.key, required this.email});

  final String email;

  @override
  ConsumerState<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends ConsumerState<VerifyEmailPage> {
  final _code = TextEditingController();
  bool _busy = false;
  int _refresh = 0;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final error = AuthRules.validateCode(_code.text);
    if (error != null) {
      showMessage(context, error, error: true);
      return;
    }
    setState(() => _busy = true);
    final ok = await _guard(
        context, () => ref.read(sessionProvider.notifier).verify(widget.email, _code.text));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      showMessage(context, 'Cuenta confirmada. ¡Bienvenido!');
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _resend() async {
    setState(() => _busy = true);
    final ok = await _guard(
        context, () => ref.read(authApiProvider).resendVerification(widget.email));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _refresh++;
    });
    if (ok) showMessage(context, 'Código enviado. Mira también en Spam.');
  }

  @override
  Widget build(BuildContext context) {
    final email = AuthRules.normalizeEmail(widget.email);
    return _AuthScaffold(
      title: 'CONFIRMAR GMAIL',
      busy: _busy,
      children: [
        Text(
          'Te enviamos un código de ${AuthRules.codeLength} dígitos a $email. '
          'Vale ${AuthRules.codeMinutes} minutos. Si no lo ves, mira en Spam.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        SimulatedMailBox(email: email, purpose: 'verify', refresh: _refresh),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          maxLength: AuthRules.codeLength,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.w800),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Código', counterText: ''),
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy ? null : _verify, child: const Text('Confirmar')),
        TextButton(onPressed: _busy ? null : _resend, child: const Text('Reenviar código')),
      ],
    );
  }
}

// ───────────────────────── Contraseña ─────────────────────────

/// Olvidé / cambiar la contraseña: siempre con un código al Gmail.
class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key, this.initialIdentifier = '', this.lockedIdentifier = false});

  final String initialIdentifier;

  /// Ya con sesión (cambiar contraseña): el usuario no se puede cambiar.
  final bool lockedIdentifier;

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> {
  late final _id = TextEditingController(text: widget.initialIdentifier);
  final _code = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _form = GlobalKey<FormState>();
  String? _sentTo;
  bool _busy = false;
  int _refresh = 0;

  @override
  void dispose() {
    for (final c in [_id, _code, _pass, _pass2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    if (_id.text.trim().isEmpty) {
      showMessage(context, 'Escribe tu usuario o Gmail', error: true);
      return;
    }
    setState(() => _busy = true);
    String? to;
    final ok = await _guard(
        context, () async => to = await ref.read(authApiProvider).requestPasswordReset(_id.text));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        _sentTo = to;
        _refresh++;
      }
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await _guard(
      context,
      () => ref.read(authApiProvider).resetPassword(
            identifier: _id.text,
            code: _code.text,
            newPassword: _pass.text,
          ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    // Las sesiones abiertas se cierran al cambiar la contraseña.
    if (ref.read(sessionProvider).value != null) {
      await ref.read(sessionProvider.notifier).logout();
      if (!mounted) return;
    }
    showMessage(context, 'Contraseña cambiada. Inicia sesión con la nueva.');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final sent = _sentTo;
    return _AuthScaffold(
      title: 'CONTRASEÑA',
      busy: _busy,
      children: [
        TextField(
          controller: _id,
          readOnly: widget.lockedIdentifier || sent != null,
          decoration: const InputDecoration(
            labelText: 'Usuario o Gmail',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 12),
        if (sent == null)
          FilledButton(
            onPressed: _busy ? null : _send,
            child: const Text('Enviarme un código al Gmail'),
          )
        else
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Te enviamos un código a $sent.',
                    style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 12),
                SimulatedMailBox(email: sent, purpose: 'reset', refresh: _refresh),
                TextFormField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: AuthRules.codeLength,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Código', counterText: ''),
                  validator: (v) => AuthRules.validateCode(v ?? ''),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pass,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña nueva',
                    helperText: 'Al menos 8 caracteres, con letras y números',
                  ),
                  validator: (v) => AuthRules.validatePassword(v ?? ''),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pass2,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Repite la contraseña nueva'),
                  validator: (v) => v != _pass.text ? 'Las contraseñas no coinciden' : null,
                ),
                const SizedBox(height: 20),
                FilledButton(
                    onPressed: _busy ? null : _save, child: const Text('Guardar contraseña')),
                TextButton(
                    onPressed: _busy ? null : _send, child: const Text('Reenviar código')),
              ],
            ),
          ),
      ],
    );
  }
}

/// Etiqueta de un rol con su color.
class RoleChip extends StatelessWidget {
  const RoleChip(this.role, {super.key});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final color = switch (role) {
      AppRole.admin => AppColors.draw,
      AppRole.organizer => AppColors.neon,
      AppRole.judge => AppColors.leaf,
      AppRole.player => AppColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 0.8),
      ),
      child: Text(role.label,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}
