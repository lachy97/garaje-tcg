import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// UUID v7: ordenable por tiempo y único entre dispositivos.
/// Permite fusionar datos de varios teléfonos en una futura sincronización.
String newId() => _uuid.v7();
