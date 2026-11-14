import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Mientras hay un torneo en juego que le importa a este teléfono (juega,
/// lo lleva o es juez), un servicio en primer plano con un aviso fijo
/// "Torneo en curso" impide que Android congele la app en segundo plano: así
/// sigue sincronizando y avisando (ronda nueva, tiempo, reportes, juez) con la
/// app minimizada. Se apaga solo cuando ya no hay torneos en juego.
/// No hace trabajo propio: la app sigue siendo la que sincroniza.
class TournamentKeeper {
  TournamentKeeper._();

  static bool _initialized = false;

  static void _init() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'garage_torneo',
        channelName: 'Torneo en curso',
        channelDescription: 'Mantiene la app activa durante el torneo para que lleguen los avisos.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Enciende o apaga el servicio. No lanza.
  static Future<void> set(bool on, {String text = 'Siguiendo tus mesas y avisos'}) async {
    try {
      _init();
      final running = await FlutterForegroundTask.isRunningService;
      if (on && !running) {
        await FlutterForegroundTask.startService(
          serviceId: 4242,
          notificationTitle: 'Torneo en curso',
          notificationText: text,
          callback: _keeperCallback,
        );
      } else if (on && running) {
        await FlutterForegroundTask.updateService(notificationTitle: 'Torneo en curso', notificationText: text);
      } else if (!on && running) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {
      // Sin servicio: los avisos llegan solo con la app abierta.
    }
  }
}

@pragma('vm:entry-point')
void _keeperCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAlive());
}

/// El servicio no hace nada por sí mismo: solo mantiene viva la app.
class _KeepAlive extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
