import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';

/// Hora de inicio del torneo: va en la misma fecha del torneo (día y hora).
/// Los torneos anteriores a la hora de inicio tienen las 00:00 (sin hora).
bool hasStartTime(DateTime d) => d.hour != 0 || d.minute != 0;

/// "14 nov 2026 · 14:00" (o solo el día si no tiene hora).
String formatStart(DateTime d, {bool long = false}) {
  final day = long ? DateFormat.yMMMMEEEEd('es').format(d) : DateFormat.yMMMd('es').format(d);
  return hasStartTime(d) ? '$day · ${DateFormat.Hm('es').format(d)}' : day;
}

/// Ya empezó: en juego o terminado, o pasada la hora de inicio. Desde
/// entonces el jugador no puede pedir plaza, darse de baja ni retirarse.
bool tournamentStarted(Tournament t, {DateTime? now}) =>
    t.status != TournamentStatus.draft || !(now ?? DateTime.now()).isBefore(t.date);

/// Elegir hora (manteniendo el día).
Future<DateTime?> pickStartTime(BuildContext context, DateTime current) async {
  final t = await showTimePicker(
    context: context,
    initialTime: hasStartTime(current) ? TimeOfDay.fromDateTime(current) : const TimeOfDay(hour: 14, minute: 0),
    helpText: 'Hora de inicio',
  );
  if (t == null) return null;
  return DateTime(current.year, current.month, current.day, t.hour, t.minute);
}

/// Elegir día (manteniendo la hora).
Future<DateTime?> pickStartDay(BuildContext context, DateTime current) async {
  final d = await showDatePicker(
    context: context,
    initialDate: current,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
  );
  if (d == null) return null;
  return DateTime(d.year, d.month, d.day, current.hour, current.minute);
}
