import 'package:drift/drift.dart';

/// En la web no hay copias de seguridad (.gtcg).
QueryExecutor openNativeFile(Object file) =>
    throw UnsupportedError('Las copias de seguridad solo funcionan en la app de Android.');
