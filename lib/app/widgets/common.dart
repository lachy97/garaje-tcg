import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/tournaments/domain/models.dart';
import '../theme.dart';

/// Pinta un AsyncValue con estados de carga y error coherentes.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.builder});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      // Mientras recarga se siguen viendo los datos anteriores (sin parpadeo).
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyState(
        icon: Icons.error_outline,
        title: 'No se pudo cargar',
        subtitle: '$e',
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.leaf),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary)),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Título de la barra con un nombre propio (torneo, jugador, mazo): en su
/// forma normal y hasta en dos líneas, para que los nombres largos no se
/// corten ("GARAGE WEEKLY #14 N…").
class NameTitle extends StatelessWidget {
  const NameTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 18, height: 1.15, letterSpacing: 0.2),
    );
  }
}

/// Botón de compartir: el mismo icono en toda la app (a la derecha del título
/// de la sección o en la barra superior).
class ShareButton extends StatelessWidget {
  const ShareButton({super.key, required this.onPressed, this.tooltip = 'Compartir'});

  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) =>
      IconButton(tooltip: tooltip, icon: const Icon(Icons.share), onPressed: onPressed);
}

/// Etiqueta de sección en mayúsculas ("MESA 1", "CONFIGURACIÓN"...).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.padding});

  final String text;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// Selector numérico − valor +.
class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.suffix,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final int step;

  /// Texto pequeño bajo el número (p. ej. "min").
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(
          onPressed: value > min ? () => onChanged((value - step).clamp(min, max)) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: suffix == null ? 44 : 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$value',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.neon)),
              if (suffix != null)
                Text(suffix!,
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ),
        IconButton.outlined(
          onPressed: value < max ? () => onChanged((value + step).clamp(min, max)) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

/// Aviso breve abajo. Los errores llevan icono y fondo rojizo, y duran más
/// para que dé tiempo a leerlos.
void showMessage(
  BuildContext context,
  String message, {
  bool error = false,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final color = error ? AppColors.loss : AppColors.neon;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: Duration(seconds: error || onAction != null ? 6 : 3),
      action: actionLabel != null && onAction != null
          ? SnackBarAction(label: actionLabel, onPressed: onAction)
          : null,
      backgroundColor: error
          ? (AppColors.isDark ? const Color(0xFF2A0F0F) : const Color(0xFFFDECEC))
          : AppColors.surfaceHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.6)),
      ),
      content: Row(
        children: [
          Icon(error ? Icons.error_outline : Icons.info_outline, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    color: error
                        ? (AppColors.isDark ? const Color(0xFFFFD6D6) : const Color(0xFF7A1212))
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ));
}

/// Lánzala dentro de una acción de [runGuarded] cuando el usuario cancela.
class ActionCancelled implements Exception {
  const ActionCancelled();
}

/// Ejecuta una acción mostrando los errores de negocio como mensaje.
/// Devuelve true si terminó sin errores.
Future<bool> runGuarded(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (success != null && context.mounted) showMessage(context, success);
    return true;
  } on ActionCancelled {
    return false;
  } on TournamentException catch (e) {
    if (context.mounted) showMessage(context, e.message, error: true);
  } on StateError catch (e) {
    if (context.mounted) showMessage(context, e.message, error: true);
  } on ArgumentError catch (e) {
    if (context.mounted) showMessage(context, '${e.message}', error: true);
  }
  return false;
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Aceptar',
  bool danger = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      actionsOverflowButtonSpacing: 10,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: AppColors.loss)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Pide un texto en un diálogo (renombrar, etc.).
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String confirm = 'Guardar',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      actionsOverflowButtonSpacing: 10,
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: Text(confirm),
        ),
      ],
    ),
  );
}
