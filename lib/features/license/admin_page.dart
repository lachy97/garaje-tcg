import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme.dart';
import '../../app/widgets/brand.dart';
import '../../app/widgets/common.dart';
import '../../core/license/admin_vault.dart';
import '../../core/license/license_codec.dart';
import '../../core/license/license_service.dart';
import '../../core/security/screen_protection.dart';
import 'license_widgets.dart';

/// Modo administrador: claves de licencias y generador de licencias.
///
/// Está en todas las copias de la app, pero solo sirve con TU clave privada:
/// las licencias firmadas con otra clave no funcionan en la app que lleva tu
/// clave pública.
class AdminPage extends ConsumerStatefulWidget {
  const AdminPage({super.key});

  @override
  ConsumerState<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends ConsumerState<AdminPage> {
  LicenseService? _service;
  SimpleKeyPair? _keyPair;
  Uint8List? _publicKey;
  String _ownCode = '';

  final _code = TextEditingController();
  final _holder = TextEditingController();
  int _months = 3;

  final _pin = TextEditingController();
  String? _pinError;
  bool _unlocking = false;
  String? _license;
  DateTime? _licenseExpires;
  bool? _screenProtection;

  @override
  void initState() {
    super.initState();
    _load();
    ScreenProtection.isEnabled().then((v) {
      if (mounted) setState(() => _screenProtection = v);
    });
  }

  @override
  void dispose() {
    _code.dispose();
    _holder.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final service = await ref.read(licenseServiceProvider.future);
    final code = await service.deviceCode();
    if (!mounted) return;
    setState(() {
      _service = service;
      _ownCode = code;
    });
  }

  /// Deja la clave descifrada en memoria mientras la pantalla está abierta.
  Future<void> _unlockWith(Uint8List seed) async {
    final kp = await LicenseCodec.keyPairFromSeed(seed);
    final pub = await LicenseCodec.publicKeyOf(kp);
    if (!mounted) return;
    setState(() {
      _keyPair = kp;
      _publicKey = pub;
    });
  }

  void _lock() => setState(() {
        _keyPair = null;
        _publicKey = null;
        _license = null;
        _pin.clear();
      });

  // ───────────────────── PIN ─────────────────────

  Future<void> _unlock() async {
    if (_unlocking) return;
    setState(() {
      _unlocking = true;
      _pinError = null;
    });
    try {
      final seed = await _service!.openAdminSeed(_pin.text);
      await _unlockWith(seed);
      _pin.clear();
    } on AdminPinException catch (e) {
      if (mounted) setState(() => _pinError = e.message);
    } finally {
      if (mounted) setState(() => _unlocking = false);
    }
  }

  /// Pide un PIN nuevo dos veces. null si se cancela.
  Future<String?> _askNewPin({String title = 'Crea tu PIN de administrador'}) {
    final a = TextEditingController();
    final b = TextEditingController();
    String? error;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('De ${AdminVault.minPinLength} a ${AdminVault.maxPinLength} números. '
                  'Lo pedirá cada vez que entres al Modo administrador. '
                  'No se puede recuperar: si lo olvidas tendrás que importar tu '
                  'clave privada de respaldo.'),
              const SizedBox(height: 12),
              _pinField(a, 'PIN'),
              const SizedBox(height: 8),
              _pinField(b, 'Repite el PIN', errorText: error),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (!AdminVault.isValidPin(a.text)) {
                  setState(() => error = 'El PIN debe tener de '
                      '${AdminVault.minPinLength} a ${AdminVault.maxPinLength} números.');
                } else if (a.text != b.text) {
                  setState(() => error = 'Los PIN no coinciden.');
                } else {
                  Navigator.pop(ctx, a.text);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _pinField(TextEditingController c, String label,
      {String? errorText, ValueChanged<String>? onSubmitted}) {
    return TextField(
      controller: c,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: AdminVault.maxPinLength,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 22, letterSpacing: 8),
      onSubmitted: onSubmitted,
      decoration: InputDecoration(labelText: label, errorText: errorText, counterText: ''),
    );
  }

  /// Guarda la clave cifrada con un PIN nuevo y la deja desbloqueada.
  Future<bool> _protectAndUnlock(Uint8List seed, {String? title}) async {
    final pin = await _askNewPin(title: title ?? 'Crea tu PIN de administrador');
    if (pin == null || !mounted) return false;
    setState(() => _unlocking = true);
    try {
      await _service!.saveAdminSeed(seed, pin);
      await _unlockWith(seed);
    } finally {
      if (mounted) setState(() => _unlocking = false);
    }
    return true;
  }

  Future<void> _changePin() async {
    final seed = await LicenseCodec.seedOf(_keyPair!);
    if (await _protectAndUnlock(seed, title: 'Nuevo PIN') && mounted) {
      showMessage(context, 'PIN cambiado');
    }
  }

  bool get _matchesApp {
    final app = LicenseService.appPublicKey;
    final mine = _publicKey;
    if (app == null || mine == null) return false;
    for (var i = 0; i < 32; i++) {
      if (app[i] != mine[i]) return false;
    }
    return true;
  }

  // ───────────────────── Claves ─────────────────────

  Future<void> _createKeys() async {
    final ok = await confirmDialog(
      context,
      title: 'Crear claves nuevas',
      message: 'Se crea tu par de claves de administrador.\n\n'
          '• La clave PRIVADA queda en este teléfono: haz una copia y guárdala en un '
          'lugar seguro (si la pierdes no podrás crear más licencias).\n'
          '• La clave PÚBLICA hay que ponerla en el código de la app y compilar.\n\n'
          'Si ya tienes claves, NO crees otras: las licencias hechas con claves '
          'distintas no sirven en la misma app.',
      confirm: 'Crear',
    );
    if (!ok) return;
    final kp = await LicenseCodec.newKeyPair();
    if (await _protectAndUnlock(await LicenseCodec.seedOf(kp)) && mounted) {
      showMessage(context, 'Claves creadas. Haz ya la copia de la clave privada.');
    }
  }

  Future<void> _importKey() async {
    final text = await promptText(context,
        title: 'Importar clave privada', label: 'GTCG-PRIV-…', confirm: 'Importar');
    if (text == null || text.isEmpty) return;
    final seed = LicenseCodec.decodePrivateKey(text);
    if (seed == null) {
      if (mounted) showMessage(context, 'Clave privada no válida.', error: true);
      return;
    }
    if (await _protectAndUnlock(seed) && mounted) {
      showMessage(context, 'Clave privada importada.');
    }
  }

  Future<void> _copyPrivate() async {
    final ok = await confirmDialog(
      context,
      title: 'Copiar clave privada',
      message: 'Quien tenga esta clave puede crear licencias para tu app. '
          'Guárdala solo en un lugar seguro (por ejemplo, una nota privada o un '
          'papel) y no la envíes a nadie.',
      confirm: 'Copiar',
    );
    if (!ok) return;
    final seed = await LicenseCodec.seedOf(_keyPair!);
    await Clipboard.setData(ClipboardData(text: LicenseCodec.encodePrivateKey(seed)));
    if (mounted) showMessage(context, 'Clave privada copiada');
  }

  Future<void> _deleteKey() async {
    final ok = await confirmDialog(
      context,
      title: 'Borrar clave de este teléfono',
      message: 'Este teléfono ya no podrá crear licencias. Las licencias ya '
          'entregadas siguen funcionando. Asegúrate de tener una copia de la clave privada.',
      confirm: 'Borrar',
      danger: true,
    );
    if (!ok) return;
    await _service!.deleteAdminSeed();
    _lock();
  }

  // ───────────────────── Generar ─────────────────────

  Future<void> _generate() async {
    final fp = LicenseCodec.parseDeviceCode(_code.text);
    if (fp == null) {
      showMessage(context, 'Código de dispositivo no válido (16 caracteres).', error: true);
      return;
    }
    final holder = _holder.text.trim();
    if (holder.isEmpty) {
      showMessage(context, 'Escribe el nombre del cliente.', error: true);
      return;
    }
    final today = DateTime.now();
    final expires = LicenseCodec.addMonths(today, _months);
    final data = LicenseData(
      fingerprint: fp,
      issuedDay: LicenseCodec.dayOf(today),
      expiresDay: LicenseCodec.dayOf(expires),
      holder: holder,
    );
    final text = await LicenseCodec.sign(data, _keyPair!);
    setState(() {
      _license = text;
      _licenseExpires = expires;
    });
  }

  String get _shareText =>
      'Licencia Garage TCG para ${_holder.text.trim()} '
      '(válida hasta el ${formatDate(_licenseExpires!)}).\n'
      'En la app: Ajustes → Licencia → Introducir licencia, y pega esto:\n\n$_license';

  @override
  Widget build(BuildContext context) {
    final service = _service;
    final hasKey = _keyPair != null;
    final Widget keyCard;
    if (service == null) {
      keyCard = const Center(child: CircularProgressIndicator());
    } else if (hasKey) {
      keyCard = _keyInfo();
    } else if (service.legacyAdminSeed != null) {
      keyCard = _legacyKey(service.legacyAdminSeed!);
    } else if (service.hasAdminKey) {
      keyCard = _locked();
    } else {
      keyCard = _noKey();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('MODO ADMINISTRADOR'),
        actions: [
          if (hasKey)
            IconButton(
              tooltip: 'Bloquear',
              onPressed: _lock,
              icon: const Icon(Icons.lock_outline),
            ),
        ],
      ),
      body: service == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                const SectionLabel('Claves de licencias'),
                NeonCard(child: keyCard),
                if (hasKey) ...[
                  const SectionLabel('Generar licencia'),
                  NeonCard(child: _generator()),
                  const SectionLabel('Seguridad'),
                  NeonCard(child: _screenProtectionTile()),
                ],
              ],
            ),
    );
  }

  /// Interruptor del bloqueo de capturas (solo con la clave desbloqueada).
  Widget _screenProtectionTile() {
    final on = _screenProtection ?? true;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: on,
      onChanged: _screenProtection == null
          ? null
          : (v) async {
              setState(() => _screenProtection = v);
              await ScreenProtection.setEnabled(v);
              if (mounted) {
                showMessage(context,
                    v ? 'Capturas bloqueadas' : 'Capturas permitidas en este teléfono');
              }
            },
      title: const Text('Bloquear capturas y grabación de pantalla'),
      subtitle: Text(
        on
            ? 'Activo: no se pueden hacer capturas ni grabar la pantalla de la app. '
                'Exportar el ranking y la tier list sigue funcionando.'
            : 'Desactivado en este teléfono: se pueden hacer capturas. '
                'Vuelve a activarlo cuando termines.',
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _locked() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.lock, size: 40, color: AppColors.neon),
        const SizedBox(height: 8),
        const Text('Introduce tu PIN de administrador',
            textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        _pinField(_pin, 'PIN', errorText: _pinError, onSubmitted: (_) => _unlock()),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _unlocking ? null : _unlock,
          icon: _unlocking
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.lock_open),
          label: const Text('Desbloquear'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _importKey,
          child: const Text('¿Olvidaste el PIN? Importa tu clave privada de respaldo'),
        ),
      ],
    );
  }

  Widget _legacyKey(Uint8List seed) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.shield_outlined, size: 40, color: AppColors.draw),
        const SizedBox(height: 8),
        const Text(
          'Tu clave privada está guardada sin protección. Crea un PIN: la clave '
          'quedará cifrada y nadie podrá generar licencias con tu teléfono sin él.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _unlocking ? null : () => _protectAndUnlock(seed),
          icon: const Icon(Icons.pin),
          label: const Text('Crear PIN'),
        ),
      ],
    );
  }

  Widget _noKey() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Este teléfono no tiene clave de administrador.\n\n'
            'Primera vez: crea las claves. Si ya las creaste en otro teléfono o en el '
            'generador del PC, importa tu clave privada.'),
        const SizedBox(height: 12),
        FilledButton.icon(
            onPressed: _createKeys,
            icon: const Icon(Icons.key),
            label: const Text('Crear claves nuevas')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: _importKey,
            icon: const Icon(Icons.download),
            label: const Text('Importar clave privada')),
      ],
    );
  }

  Widget _keyInfo() {
    final pub = LicenseCodec.encodePublicKey(_publicKey!);
    final (status, color) = LicenseService.appPublicKey == null
        ? (
            'Esta versión de la app aún no tiene clave pública: pégala en '
                'lib/core/license/license_config.dart y compila.',
            AppColors.draw
          )
        : _matchesApp
            ? ('Coincide con la clave de esta app ✓', AppColors.neon)
            : (
                'NO coincide con la clave de esta app: las licencias que generes '
                    'aquí no servirán en esta versión.',
                AppColors.loss
              );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Clave pública (va en el código de la app)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        SelectableText(pub,
            style: const TextStyle(fontSize: 13, color: AppColors.neon)),
        const SizedBox(height: 6),
        Text(status, style: TextStyle(fontSize: 13, color: color)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: pub));
                if (mounted) showMessage(context, 'Clave pública copiada');
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copiar pública'),
            ),
            OutlinedButton.icon(
              onPressed: _copyPrivate,
              icon: const Icon(Icons.lock_outline, size: 18),
              label: const Text('Copiar privada (respaldo)'),
            ),
            OutlinedButton.icon(
              onPressed: _changePin,
              icon: const Icon(Icons.pin, size: 18),
              label: const Text('Cambiar PIN'),
            ),
            TextButton.icon(
              onPressed: _deleteKey,
              icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.loss),
              label: const Text('Borrar de este teléfono',
                  style: TextStyle(color: AppColors.loss)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _generator() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Código del dispositivo del cliente',
            hintText: 'XXXX-XXXX-XXXX-XXXX',
            suffixIcon: IconButton(
              tooltip: 'Pegar',
              icon: const Icon(Icons.content_paste),
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                final match = RegExp(r'[0-9A-Za-z]{4}-[0-9A-Za-z]{4}-[0-9A-Za-z]{4}-[0-9A-Za-z]{4}')
                    .firstMatch(data?.text ?? '');
                _code.text = match?.group(0) ?? (data?.text ?? '').trim();
              },
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _code.text = _ownCode),
            child: Text('Usar este teléfono ($_ownCode)'),
          ),
        ),
        TextField(
          controller: _holder,
          maxLength: LicenseCodec.maxHolderBytes,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Cliente (nombre que verá en la app)'),
        ),
        const SizedBox(height: 4),
        const Text('Duración', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final m in const [1, 2, 3, 6, 12, 24])
              ChoiceChip(
                label: Text(m == 1 ? '1 mes' : '$m meses'),
                selected: _months == m,
                onSelected: (_) => setState(() => _months = m),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(child: Text('Otra duración (meses)')),
            NumberStepper(
              value: _months,
              min: 1,
              max: 240,
              onChanged: (v) => setState(() => _months = v),
            ),
          ],
        ),
        Text(
          'Válida desde hoy hasta el ${formatDate(LicenseCodec.addMonths(DateTime.now(), _months))}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _generate,
          icon: const Icon(Icons.verified_outlined),
          label: const Text('GENERAR LICENCIA'),
        ),
        if (_license != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.neon),
            ),
            child: SelectableText(_license!, style: const TextStyle(fontSize: 12.5)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.icon(
                onPressed: () => SharePlus.instance.share(ShareParams(text: _shareText)),
                icon: const Icon(Icons.send),
                label: const Text('Enviar'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _license!));
                  if (mounted) showMessage(context, 'Licencia copiada');
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copiar'),
              ),
              if (_code.text.replaceAll('-', '').toUpperCase() ==
                  _ownCode.replaceAll('-', ''))
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await ref.read(licenseProvider.notifier).activate(_license!);
                      if (mounted) showMessage(context, 'Licencia activada en este teléfono');
                    } on LicenseFormatException catch (e) {
                      if (mounted) showMessage(context, e.message, error: true);
                    }
                  },
                  icon: const Icon(Icons.phone_android, size: 18),
                  label: const Text('Activar aquí'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
