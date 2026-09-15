import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Time-ordered identifier.
///
/// v7 keeps ids sortable by creation time, which makes them stable primary
/// keys for a future sync backend and keeps index locality good in SQLite.
String newId() => _uuid.v7();
