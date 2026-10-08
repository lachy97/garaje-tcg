import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart' show rootNavigatorKey;
import '../../app/theme.dart';
import '../../app/widgets/brand.dart';
import '../../app/widgets/common.dart';
import '../../core/backup/backup_service.dart';
import '../../core/license/license_service.dart';
import 'admin_page.dart';
import 'license_widgets.dart';

/// Envuelve toda la app: si la licencia no permite usarla muestra la pantalla
/// de bloqueo. Vuelve a comprobar al regresar a la app (p. ej. a medianoche
/// del día de vencimiento o tras corregir la fecha).
class LicenseGate extends ConsumerStatefulWidget {
  const LicenseGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LicenseGate> createState() => _LicenseGateState();
}

class _LicenseGateState extends ConsumerState<LicenseGate> with WidgetsBindingObserver {
  bool _warningScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(licenseProvider.notifier).refresh();
    }
  }

  void _maybeWarn(LicenseStatus s) {
    if (_warningScheduled || s.state != LicenseState.expiringSoon) return;
    _warningScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final service = await ref.read(licenseServiceProvider.future);
      if (!await service.shouldWarnToday()) return;
      final ctx = rootNavigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      final (text, _) = licenseSummary(s);
      await showDialog<void>(
        context: ctx,
        builder: (dctx) => AlertDialog(
          icon: const Icon(Icons.event_busy, color: AppColors.draw, size: 36),
          title: const Text('Licencia por vencer'),
          content: Text('$text\n\nEnvía el código de este teléfono al administrador '
              'para renovarla: ${s.deviceCode}'),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(dctx), child: const Text('Entendido')),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(licenseProvider);
    return status.when(
      // Si algo inesperado falla al comprobar, no se bloquea a nadie en medio
      // de un torneo; se volverá a comprobar al regresar a la app.
      error: (_, _) => widget.child,
      loading: () => status.hasValue && status.value!.allowsUse
          ? widget.child
          : const _Splash(),
      data: (s) {
        if (s.allowsUse) {
          _maybeWarn(s);
          return widget.child;
        }
        // Navigator propio para poder abrir diálogos y el modo administrador.
        return Navigator(
          onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const LockScreen()),
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: GlowLogo(size: 120)));
  }
}

/// Pantalla cuando no hay licencia válida: código del teléfono, introducir
/// licencia y exportar los datos (los datos nunca quedan secuestrados).
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  int _logoTaps = 0;

  void _onLogoTap() {
    // 7 toques en el logo abren el modo administrador (para activar tu propio
    // teléfono aunque esté bloqueado).
    if (++_logoTaps >= 7) {
      _logoTaps = 0;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(licenseProvider).value;
    if (s == null) return const _Splash();
    final (summary, color) = licenseSummary(s);
    final title = switch (s.state) {
      LicenseState.expired => 'Licencia vencida',
      LicenseState.missing => 'Activa Garage TCG',
      LicenseState.clockBack => 'Revisa la fecha',
      _ => 'Licencia no válida',
    };
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
          children: [
            Center(
              child: GestureDetector(onTap: _onLogoTap, child: const GlowLogo(size: 110)),
            ),
            const SizedBox(height: 12),
            const Center(child: BrandTitle(fontSize: 24)),
            const SizedBox(height: 24),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(summary,
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              s.state == LicenseState.clockBack
                  ? 'Corrige la fecha y la hora en los ajustes del teléfono y vuelve a la app.'
                  : 'Envía el código de este teléfono al administrador. Te devolverá una '
                      'licencia; tócala para copiarla y pégala aquí.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            DeviceCodeCard(code: s.deviceCode),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => showActivateLicenseDialog(context, ref),
              icon: const Icon(Icons.vpn_key),
              label: const Text('INTRODUCIR LICENCIA'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => ref.read(licenseProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('Volver a comprobar'),
            ),
            const SizedBox(height: 28),
            const Text('Tus datos siguen guardados en el teléfono. Puedes sacar una copia:',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            TextButton.icon(
              onPressed: () async {
                try {
                  await ref.read(backupServiceProvider).share();
                } catch (e) {
                  if (context.mounted) {
                    showMessage(context, 'No se pudo exportar: $e', error: true);
                  }
                }
              },
              icon: const Icon(Icons.upload_file),
              label: const Text('Exportar base de datos'),
            ),
          ],
        ),
      ),
    );
  }
}
