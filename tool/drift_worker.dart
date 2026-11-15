// Worker de Drift para la versión web (se compila a web/drift_worker.js):
//   dart compile js -O4 -o web/drift_worker.js tool/drift_worker.dart
import 'package:drift/wasm.dart';

void main() => WasmDatabase.workerMainForOpen();
