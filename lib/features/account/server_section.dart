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

  /// Pide la dirección a probar (para la fase 0, antes de compilarla en la app).
  Future<void> _testOther() async {
    final ctrl = TextEditingController(text: kServerUrl.isEmpty ? 'https://' : kServerUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
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
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (real != null)
            FilledButton.icon(
              onPressed: _busy ? null : () => _test(real.baseUrl),
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Probar conexión'),
            ),
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
                  Expanded(child: Text(_result!)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
