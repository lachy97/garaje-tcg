import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/restartable_app.dart';
import '../../app/theme.dart';
import '../../app/widgets/brand.dart';
import '../../app/widgets/common.dart';
import '../../core/backup/backup_codec.dart';
import '../../core/backup/backup_service.dart';
import '../../core/license/license_service.dart';
import '../license/license_widgets.dart';

final _packageInfoProvider = FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

/// Ajustes: licencia, copia de seguridad y datos de la app.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _busy = false;
  bool? _adminUnlocked;

  @override
  void initState() {
    super.initState();
    // El Modo administrador solo existe en el teléfono del administrador.
    ref.read(licenseServiceProvider.future).then((s) => s.isAdminDevice()).then((v) {
      if (mounted) setState(() => _adminUnlocked = v);
    });
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on BackupException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) showMessage(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ───────────────────── Copia de seguridad ─────────────────────

  Future<void> _export() async {
    final where = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share, color: AppColors.neon),
              title: const Text('Compartir'),
              subtitle: const Text('WhatsApp, Telegram, Bluetooth, Drive…'),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.save_alt, color: AppColors.neon),
              title: const Text('Guardar en el teléfono'),
              subtitle: const Text('Elige una carpeta (p. ej. Descargas)'),
              onTap: () => Navigator.pop(ctx, 'save'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (where == null) return;
    await _guard(() async {
      final service = ref.read(backupServiceProvider);
      if (where == 'share') {
        await service.share();
      } else if (await service.saveToDevice() && mounted) {
        showMessage(context, 'Copia guardada');
      }
    });
  }

  Future<void> _import() async {
    await _guard(() async {
      final service = ref.read(backupServiceProvider);
      final preview = await service.pickAndInspect();
      if (preview == null || !mounted) return;
      await _confirmAndRestore(preview);
    });
  }

  Future<void> _restoreAuto() async {
    final service = ref.read(backupServiceProvider);
    final autos = await service.autoBackups();
    if (!mounted) return;
    if (autos.isEmpty) {
      showMessage(context, 'No hay copias automáticas todavía.');
      return;
    }
    final chosen = await showDialog<AutoBackup>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Copias automáticas'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Se guardan solas antes de cada importación (las 5 últimas).',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ),
          for (final a in autos)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, a),
              child: Text('Datos del ${DateFormat('dd/MM/yyyy HH:mm').format(a.date)}',
                  style: const TextStyle(fontSize: 16)),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    await _guard(() async {
      final preview = await service.inspectAuto(chosen);
      if (mounted) await _confirmAndRestore(preview);
    });
  }

  Future<void> _confirmAndRestore(BackupPreview preview) async {
    final h = preview.header;
    final ok = await confirmDialog(
      context,
      title: 'Importar base de datos',
      message: 'Copia del ${DateFormat('dd/MM/yyyy HH:mm').format(h.exportedAt)}\n'
          '${h.players} jugadores · ${h.tournaments} torneos · ${h.decks} mazos\n\n'
          'Se REEMPLAZARÁN todos los datos de este teléfono por los de la copia. '
          'Antes se guarda una copia automática de los datos actuales por si '
          'necesitas volver atrás.',
      confirm: 'Importar',
      danger: true,
    );
    if (!ok || !mounted) return;
    final applied = await ref.read(backupServiceProvider).restore(preview);
    if (!mounted) return;
    if (applied) {
      // Se vuelven a crear la BD y todas las pantallas con los datos nuevos.
      RestartableApp.restart();
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Falta un paso'),
        content: const Text(
            'La copia está lista. Cierra la app por completo y vuelve a abrirla '
            'para terminar la importación.'),
        actions: [
          FilledButton(
            onPressed: () => SystemNavigator.pop(),
            child: const Text('Cerrar la app'),
          ),
        ],
      ),
    );
  }

  // ───────────────────── Acerca de ─────────────────────

  @override
  Widget build(BuildContext context) {
    final license = ref.watch(licenseProvider);
    final info = ref.watch(_packageInfoProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('AJUSTES')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              const SectionLabel('Licencia'),
              NeonCard(
                child: AsyncView(
                  value: license,
                  builder: (s) {
                    final (text, color) = licenseSummary(s);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (s.data != null && s.data!.holder.isNotEmpty)
                          Text(s.data!.holder,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800)),
                        Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        DeviceCodeCard(code: s.deviceCode),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => showActivateLicenseDialog(context, ref),
                          icon: const Icon(Icons.vpn_key),
                          label: Text(s.data == null
                              ? 'Introducir licencia'
                              : 'Introducir licencia nueva / renovación'),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SectionLabel('Copia de seguridad'),
              NeonCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Guarda todos los datos (jugadores, mazos, torneos, ranking) en un '
                      'archivo .gtcg. Se puede cargar en cualquier teléfono con Garage TCG. '
                      'Solo se aceptan archivos exportados por esta app.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _busy ? null : _export,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Exportar base de datos'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _import,
                      icon: const Icon(Icons.download),
                      label: const Text('Importar base de datos'),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _restoreAuto,
                      icon: const Icon(Icons.history),
                      label: const Text('Deshacer una importación (copias automáticas)'),
                    ),
                  ],
                ),
              ),
              if (_adminUnlocked ?? false) ...[
                const SectionLabel('Administrador'),
                NeonCard(
                  onTap: () => context.push('/ajustes/admin'),
                  child: const Row(
                    children: [
                      Icon(Icons.admin_panel_settings, color: AppColors.neon),
                      SizedBox(width: 12),
                      Expanded(child: Text('Modo administrador (claves y licencias)')),
                      Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ],
              const SectionLabel('Acerca de'),
              NeonCard(
                child: Row(
                  children: [
                    const GlowLogo(size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Garage TCG',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          Text(
                            info == null
                                ? 'Versión…'
                                : 'Versión ${info.version} (${info.buildNumber})',
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_busy)
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
