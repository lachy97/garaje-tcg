import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:share_plus/share_plus.dart';

import '../../app/theme.dart';
import '../../app/widgets/common.dart';
import '../../core/license/license_codec.dart';
import '../../core/license/license_service.dart';

String formatDate(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

/// Código del dispositivo con botones de copiar y enviar.
class DeviceCodeCard extends StatelessWidget {
  const DeviceCodeCard({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CÓDIGO DE ESTE TELÉFONO',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                SelectableText(code,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: AppColors.neon)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copiar',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (context.mounted) showMessage(context, 'Código copiado');
            },
          ),
          IconButton(
            tooltip: 'Enviar al administrador',
            icon: const Icon(Icons.send),
            onPressed: () => SharePlus.instance.share(ShareParams(
              text: 'Hola, necesito una licencia de Garage TCG.\n'
                  'Código de mi teléfono: $code',
            )),
          ),
        ],
      ),
    );
  }
}

/// Diálogo para pegar una licencia nueva o una renovación.
/// Devuelve true si se activó.
Future<bool> showActivateLicenseDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  String? error;
  var busy = false;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Introducir licencia'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Pega la licencia que te envió el administrador '
                  '(empieza por GTCG1.).'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 3,
                maxLines: 6,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'GTCG1.…',
                  errorText: error,
                  errorMaxLines: 4,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    final text = data?.text ?? '';
                    // Si se pegó el mensaje completo, se extrae solo la licencia.
                    final match = RegExp(r'GTCG1\.[A-Za-z0-9_\-]+').firstMatch(text);
                    controller.text = match?.group(0) ?? text;
                  },
                  icon: const Icon(Icons.content_paste),
                  label: const Text('Pegar'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      final text = RegExp(r'GTCG1\.[A-Za-z0-9_\-]+')
                              .firstMatch(controller.text.replaceAll(RegExp(r'\s'), ''))
                              ?.group(0) ??
                          controller.text;
                      await ref.read(licenseProvider.notifier).activate(text);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } on LicenseFormatException catch (e) {
                      setState(() {
                        busy = false;
                        error = e.message;
                      });
                    }
                  },
            child: const Text('Activar'),
          ),
        ],
      ),
    ),
  );
  if (ok == true && context.mounted) {
    final data = ref.read(licenseProvider).value?.data;
    showMessage(
        context,
        data == null
            ? 'Licencia activada'
            : 'Licencia activada hasta el ${formatDate(data.expires)}');
  }
  return ok ?? false;
}

/// Texto corto del estado de la licencia.
(String, Color) licenseSummary(LicenseStatus s) {
  final d = s.data;
  return switch (s.state) {
    LicenseState.notConfigured => (
        'Licencias sin configurar: la app funciona sin licencia.',
        AppColors.textSecondary
      ),
    LicenseState.valid => (
        'Activa hasta el ${formatDate(d!.expires)} (quedan ${s.daysLeft} días)',
        AppColors.neon
      ),
    LicenseState.expiringSoon => (
        s.daysLeft == 0
            ? 'Vence HOY (${formatDate(d!.expires)}). Pide la renovación.'
            : 'Vence en ${s.daysLeft} día(s), el ${formatDate(d!.expires)}. Pide la renovación.',
        AppColors.draw
      ),
    LicenseState.missing => ('Este teléfono no tiene licencia.', AppColors.loss),
    LicenseState.expired => ('Licencia vencida el ${formatDate(d!.expires)}.', AppColors.loss),
    LicenseState.wrongDevice => (
        'La licencia guardada es de otro teléfono (${d!.deviceCode}).',
        AppColors.loss
      ),
    LicenseState.invalid => (s.message ?? 'Licencia no válida.', AppColors.loss),
    LicenseState.clockBack => (s.message ?? 'Fecha del teléfono incorrecta.', AppColors.loss),
  };
}
