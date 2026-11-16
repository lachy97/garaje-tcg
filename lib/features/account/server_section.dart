import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/widgets/brand.dart';
import '../../app/widgets/common.dart';
import '../../core/auth/account.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/auth/http_auth_api.dart';
import '../../core/auth/server_config.dart';

/// Ajustes → Servidor: a qué servidor de cuentas está conectada la app y
/// prueba de conexión (fase 0: ¿responde desde Cuba con o sin VPN?).
class ServerSection extends ConsumerStatefulWidget {
  const ServerSection({super.key});

  @override
  ConsumerState<ServerSection> createState() => _ServerSectionState();
}

class _ServerSectionState extends ConsumerState<ServerSection> {
  bool _busy = false;
  String? _result;
  bool _ok = false;

  Future<void> _test(String url) async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final r = await HttpAuthApi(url, timeout: const Duration(seconds: 15)).health();
      _ok = true;
      _result = 'Responde en ${r.latency.inMilliseconds} ms (versión ${r.version}).';
    } on AuthException catch (e) {
      _ok = false;
      _result = e.message;
    } catch (e) {
      _ok = false;
      _result = 'No se pudo conectar: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Administrador: manda un correo de prueba a su Gmail y muestra el error
  /// exacto si falla (para configurar el envío de códigos).
  Future<void> _mailTest(HttpAuthApi api) async {
    final session = ref.read(sessionProvider).value;
    if (session == null) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final r = await api.request('POST', 'v1/admin/mail-test', body: const {}, token: session.token);
      _ok = r['ok'] == true;
      final via = switch (r['provider']) {
        'gmail' => 'Gmail del club',
        'sendpulse' => 'SendPulse',
        'brevo' => 'Brevo',
        _ => 'sin proveedor',
      };
      _result = _ok
          ? 'Correo de prueba enviado a ${r['to']} ($via). Revisa la bandeja y Spam.'
          : 'No se pudo enviar ($via): ${r['error']}';
    } on AuthException catch (e) {
      _ok = false;
      _result = e.message;
    } catch (e) {
      _ok = false;
      _result = 'No se pudo conectar: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Pide la dirección a probar (para la fase 0, antes de compilarla en la app).
  Future<void> _testOther() async {
    final ctrl = TextEditingController(text: kServerUrl.isEmpty ? 'https://' : kServerUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        actionsOverflowButtonSpacing: 10,
        title: const Text('Probar servidor'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Dirección',
            hintText: 'https://garage-tcg-api.xxx.workers.dev',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Probar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (url == null || !mounted) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      showMessage(context, 'Dirección no válida', error: true);
      return;
    }
    await _test(url);
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(authApiProvider);
    final real = api is HttpAuthApi ? api : null;
    return NeonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            real == null ? 'Servidor simulado en este teléfono' : real.baseUrl,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            real == null
                ? 'Las cuentas se guardan solo aquí hasta conectar la app con el servidor.'
                : 'Cuentas en el servidor de Garage TCG (Cloudflare).',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (real != null)
            FilledButton.icon(
              onPressed: _busy ? null : () => _test(real.baseUrl),
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Probar conexión'),
            ),
          if (real != null) const SizedBox(height: 10),
          if (real != null &&
              ref.watch(sessionProvider).value?.account.role == AppRole.admin) ...[
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _mailTest(real),
              icon: const Icon(Icons.mark_email_read_outlined),
              label: const Text('Enviarme un correo de prueba'),
            ),
            const SizedBox(height: 10),
            _MinVersion(api: real),
            const SizedBox(height: 10),
          ],
          OutlinedButton.icon(
            onPressed: _busy ? null : _testOther,
            icon: const Icon(Icons.travel_explore),
            label: Text(real == null ? 'Probar conexión con un servidor' : 'Probar otra dirección'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_result != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Icon(_ok ? Icons.check_circle : Icons.error_outline,
                      color: _ok ? AppColors.neon : AppColors.loss),
                  const SizedBox(width: 8),
                  Expanded(child: SelectableText(_result!)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Administrador: versión mínima de la app. Al publicar un APK nuevo (y
/// tenerlo instalado), "Exigir mi versión" obliga a todos a actualizar: las
/// anteriores quedan bloqueadas en la pantalla de actualizar. La web no se
/// bloquea nunca (siempre es la última).
class _MinVersion extends ConsumerStatefulWidget {
  const _MinVersion({required this.api});

  final HttpAuthApi api;

  @override
  ConsumerState<_MinVersion> createState() => _MinVersionState();
}

class _MinVersionState extends ConsumerState<_MinVersion> {
  int? _min;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? get _token => ref.read(sessionProvider).value?.token;

  Future<void> _load() async {
    try {
      final r = await widget.api.request('GET', 'v1/admin/app-version', token: _token);
      if (mounted) setState(() => _min = (r['minBuild'] as num?)?.toInt() ?? 0);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo leer: $e');
    }
  }

  Future<void> _set(int n) async {
    final mine = HttpAuthApi.appBuild;
    final ok = await confirmDialog(
      context,
      title: n == 0 ? 'Quitar la versión mínima' : 'Exigir la compilación $n',
      message: n == 0
          ? 'Cualquier versión de la app podrá volver a usar el servidor.'
          : 'Los teléfonos con una versión anterior a la $n quedarán bloqueados en la pantalla '
              '"Actualización obligatoria" hasta instalar la nueva. '
              'Hazlo cuando el APK nuevo ya esté en el grupo de WhatsApp.'
              '${n > mine ? '\n\nOJO: tu propia app (compilación $mine) también quedará bloqueada.' : ''}',
      confirm: n == 0 ? 'Quitar' : 'Exigir',
      danger: n > 0,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await widget.api.request('POST', 'v1/admin/app-version', body: {'minBuild': n}, token: _token);
      if (mounted) {
        setState(() => _min = (r['minBuild'] as num?)?.toInt() ?? n);
        showMessage(context, n == 0 ? 'Sin versión mínima' : 'Versión mínima: compilación $n');
      }
    } on AuthException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) showMessage(context, 'No se pudo: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = HttpAuthApi.appBuild;
    final web = kIsWeb;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Versión obligatoria de la app', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            _error ??
                (_min == null
                    ? 'Leyendo…'
                    : '${_min == 0 ? 'Sin mínimo: cualquier versión puede entrar.' : 'Mínimo: compilación $_min.'}'
                        '${web ? '' : ' Tu app: compilación $mine.'}'),
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!web && mine > 0 && _min != mine)
                  FilledButton.icon(
                    onPressed: () => _set(mine),
                    icon: const Icon(Icons.system_update),
                    label: Text('Exigir mi versión ($mine)'),
                  ),
                if ((_min ?? 0) > 0)
                  TextButton(onPressed: () => _set(0), child: const Text('Quitar el mínimo')),
              ],
            ),
        ],
      ),
    );
  }
}
