// Quita la pantalla "Cargando…" cuando Flutter pinta el primer fotograma.
// (En un archivo aparte: la política de seguridad no admite scripts en línea.)
window.addEventListener('flutter-first-frame', function () {
  var c = document.getElementById('carga');
  if (c) c.remove();
});
