/// Teléfonos donde aparece el Modo administrador (claves, licencias y
/// bloqueo de capturas). En todos los demás no se muestra ni se puede abrir.
///
/// Es el "Código de este teléfono" de Ajustes → Licencia. Si cambias de
/// teléfono o lo restableces de fábrica, el código cambia: añade el nuevo aquí
/// y vuelve a compilar.
const Set<String> kAdminDeviceCodes = {
  'QT4Q-G5NW-BHMW-BJY4', // Lachy
};

/// true si [deviceCode] es de un teléfono administrador (ignora guiones,
/// espacios y mayúsculas).
bool isAdminDeviceCode(String deviceCode) {
  String norm(String s) => s.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  final code = norm(deviceCode);
  return kAdminDeviceCodes.any((c) => norm(c) == code);
}
