import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// Abre un archivo SQLite (copias de seguridad). Solo Android.
QueryExecutor openNativeFile(File file) => NativeDatabase(file);
