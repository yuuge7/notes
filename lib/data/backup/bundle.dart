import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'package:notes/data/media/media_store.dart';
import 'package:notes/domain/model/attachment.dart';
import 'package:notes/domain/model/checklist_item.dart';
import 'package:notes/domain/model/label.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/note_type.dart';
import 'package:notes/domain/model/pigment.dart';
import 'package:notes/domain/model/reminder_rule.dart';

/// An export: every note, label, and image, as a zip that reads without the
/// app.
///
/// ```text
/// manifest.json          { app, schemaVersion, appVersion, exportedAt, counts }
/// notes.json             [ notes with their items, label ids, reminder, images ]
/// labels.json            [ labels ]
/// media/<id>.jpg         each image
/// media/thumbs/<id>.jpg  its thumbnail, so an import need not remake it
/// ```
///
/// Times are UTC in ISO 8601 with milliseconds, so they read the same in any
/// time zone and come back to the millisecond.
class Bundle {
  const Bundle({
    required this.notes,
    required this.labels,
    this.appVersion = '',
    this.exportedAt,
    this.missingImages = 0,
  });

  /// Version of this layout. It is the bundle's own, not the database's: the
  /// database can change without changing what an export holds.
  static const schemaVersion = 1;

  /// Marks a manifest as this app's, so another app's zip is not mistaken for
  /// an export.
  static const app = 'notes';

  static const manifestEntry = 'manifest.json';
  static const notesEntry = 'notes.json';
  static const labelsEntry = 'labels.json';

  static const mimeType = 'application/zip';

  /// Notes in grid order, trashed and archived ones included.
  final List<Note> notes;

  /// Labels in the order set on the labels page.
  final List<Label> labels;
  final String appVersion;
  final DateTime? exportedAt;

  /// Images the notes listed that were not in the file, and were left out.
  final int missingImages;

  int get imageCount =>
      notes.fold(0, (sum, note) => sum + note.attachments.length);

  /// `notes-export-YYYYMMDD-HHmm.zip`, in local time.
  static String fileName(DateTime at) =>
      'notes-export-${DateFormat('yyyyMMdd-HHmm').format(at)}.zip';

  static String imageEntry(Attachment image) =>
      'media/${image.id}.${_extensions[image.mime] ?? 'jpg'}';

  static String thumbEntry(Attachment image) => 'media/thumbs/${image.id}.jpg';

  static const _extensions = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
    'image/gif': 'gif',
    'image/heic': 'heic',
  };

  Bundle copyWith({List<Note>? notes, int? missingImages}) => Bundle(
    notes: notes ?? this.notes,
    labels: labels,
    appVersion: appVersion,
    exportedAt: exportedAt,
    missingImages: missingImages ?? this.missingImages,
  );

  // Writing -------------------------------------------------------------------

  String manifestJson() => _encoder.convert({
    'app': app,
    'schemaVersion': schemaVersion,
    'appVersion': appVersion,
    'exportedAt': _time(exportedAt ?? DateTime.now()),
    'counts': {
      'notes': notes.length,
      'labels': labels.length,
      'images': imageCount,
    },
  });

  String notesJson() =>
      _encoder.convert([for (final note in notes) _note(note)]);

  String labelsJson() => _encoder.convert([
    for (final label in labels)
      {
        'id': label.id,
        'name': label.name,
        'sortKey': label.sortKey,
        'updatedAt': _time(label.updatedAt),
      },
  ]);

  static const _encoder = JsonEncoder.withIndent('  ');

  /// Milliseconds are what the database keeps; a clock's microseconds are
  /// dropped.
  static String _time(DateTime at) => DateTime.fromMillisecondsSinceEpoch(
    at.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();

  static Map<String, Object?> _note(Note note) => {
    'id': note.id,
    'type': note.type.name,
    'title': note.title,
    'body': note.body,
    'pigment': note.pigment.name,
    'pinned': note.pinned,
    'archived': note.archived,
    'trashedAt': note.deleted && note.deletedAt != null
        ? _time(note.deletedAt!)
        : null,
    'sortKey': note.sortKey,
    'createdAt': _time(note.createdAt),
    'updatedAt': _time(note.updatedAt),
    'reminder': note.reminderAt == null
        ? null
        : {
            'at': _time(note.reminderAt!),
            'repeat': note.reminderRule?.name,
            'done': note.reminderDone,
          },
    'items': [
      for (final item in note.items)
        {
          'id': item.id,
          'text': item.text,
          'checked': item.checked,
          'indent': item.indent,
          'sortKey': item.sortKey,
          'updatedAt': _time(item.updatedAt),
        },
    ],
    'labels': [for (final label in note.labels) label.id],
    'images': [
      for (final image in note.attachments)
        {
          'id': image.id,
          'file': imageEntry(image),
          'width': image.width,
          'height': image.height,
          'bytes': image.bytes,
          'mime': image.mime,
          'sortKey': image.sortKey,
          'createdAt': _time(image.createdAt),
        },
    ],
  };

  // Reading -------------------------------------------------------------------

  /// Reads a bundle from the text of its three JSON entries.
  ///
  /// Throws [BundleException] when the manifest is not this app's, when the
  /// export comes from a newer version of the app, or when anything in it is
  /// missing or malformed. Values this version does not know, such as a
  /// colour added later, fall back to the default rather than failing.
  static Bundle decode({
    required String? manifest,
    required String? notes,
    required String? labels,
  }) {
    if (manifest == null) {
      throw const BundleException(BundleProblem.notAnExport);
    }
    final Object? manifestValue;
    try {
      manifestValue = jsonDecode(manifest);
    } on FormatException {
      throw const BundleException(BundleProblem.notAnExport);
    }
    if (manifestValue is! Map<String, Object?> || manifestValue['app'] != app) {
      throw const BundleException(BundleProblem.notAnExport);
    }
    final version = manifestValue['schemaVersion'];
    if (version is! int || version < 1) {
      throw const BundleException(BundleProblem.damaged, 'schemaVersion');
    }
    if (version > schemaVersion) {
      throw const BundleException(BundleProblem.newerVersion);
    }

    try {
      final head = _Fields(manifestValue, 'manifest');
      final labelList = [
        for (final (index, value) in _list(labels, 'labels').indexed)
          _label(_Fields.of(value, 'label $index')),
      ];
      final labelsById = {for (final label in labelList) label.id: label};
      final noteList = [
        for (final (index, value) in _list(notes, 'notes').indexed)
          _readNote(_Fields.of(value, 'note $index'), labelsById),
      ];
      _requireUnique([for (final label in labelList) label.id], 'label');
      _requireUnique([for (final note in noteList) note.id], 'note');
      _requireUnique([
        for (final note in noteList) ...note.items.map((item) => item.id),
      ], 'item');
      _requireUnique([
        for (final note in noteList)
          ...note.attachments.map((image) => image.id),
      ], 'image');

      return Bundle(
        notes: noteList,
        labels: labelList,
        appVersion: head.stringOr('appVersion', ''),
        exportedAt: head.timeOrNull('exportedAt'),
      );
    } on BundleException {
      rethrow;
    } on Object catch (error) {
      throw BundleException(BundleProblem.damaged, '$error');
    }
  }

  static List<Object?> _list(String? text, String what) {
    if (text == null) {
      throw BundleException(BundleProblem.damaged, '$what missing');
    }
    final value = jsonDecode(text);
    if (value is! List<Object?>) {
      throw BundleException(BundleProblem.damaged, '$what is not a list');
    }
    return value;
  }

  static void _requireUnique(List<String> ids, String what) {
    final seen = <String>{};
    final twice = ids.firstWhereOrNull((id) => !seen.add(id));
    if (twice != null) {
      throw BundleException(
        BundleProblem.damaged,
        '$what $twice appears twice',
      );
    }
  }

  static Label _label(_Fields fields) => Label(
    id: fields.id('id'),
    name: fields.string('name'),
    sortKey: fields.sortKey('sortKey'),
    updatedAt: fields.time('updatedAt'),
  );

  static Note _readNote(_Fields fields, Map<String, Label> labelsById) {
    final id = fields.id('id');
    final trashedAt = fields.timeOrNull('trashedAt');
    final reminder = fields.fieldsOrNull('reminder');
    return Note(
      id: id,
      type:
          _named(NoteType.values, fields.stringOr('type', '')) ?? NoteType.text,
      title: fields.stringOr('title', ''),
      body: fields.stringOr('body', ''),
      pigment:
          _named(Pigment.values, fields.stringOr('pigment', '')) ??
          Pigment.graphite,
      pinned: fields.flag('pinned'),
      archived: fields.flag('archived'),
      deleted: trashedAt != null,
      deletedAt: trashedAt,
      sortKey: fields.sortKey('sortKey'),
      createdAt: fields.time('createdAt'),
      updatedAt: fields.time('updatedAt'),
      reminderAt: reminder?.time('at'),
      reminderRule: reminder == null
          ? null
          : _named(ReminderRule.values, reminder.stringOr('repeat', '')),
      reminderDone: reminder?.flag('done') ?? false,
      items: [
        for (final (index, value) in fields.list('items').indexed)
          _item(_Fields.of(value, 'item $index of note $id'), id),
      ],
      // A label the file does not list is passed over, not an error.
      labels: [
        for (final labelId in fields.list('labels')) ?labelsById[labelId],
      ],
      attachments: [
        for (final (index, value) in fields.list('images').indexed)
          _image(_Fields.of(value, 'image $index of note $id'), id),
      ],
    );
  }

  static ChecklistItem _item(_Fields fields, String noteId) => ChecklistItem(
    id: fields.id('id'),
    noteId: noteId,
    text: fields.stringOr('text', ''),
    checked: fields.flag('checked'),
    indent: fields.integer('indent').clamp(0, 1),
    sortKey: fields.sortKey('sortKey'),
    updatedAt: fields.time('updatedAt'),
  );

  static Attachment _image(_Fields fields, String noteId) {
    final id = fields.id('id');
    final mime = fields.string('mime');
    if (!_extensions.containsKey(mime)) {
      throw BundleException(BundleProblem.damaged, 'image $id is $mime');
    }
    return Attachment(
      id: id,
      noteId: noteId,
      relPath: MediaStore.imagePathFor(id),
      thumbPath: MediaStore.thumbPathFor(id),
      width: fields.integer('width'),
      height: fields.integer('height'),
      bytes: fields.integer('bytes'),
      mime: mime,
      sortKey: fields.sortKey('sortKey'),
      createdAt: fields.time('createdAt'),
    );
  }

  static T? _named<T extends Enum>(List<T> values, String name) =>
      values.firstWhereOrNull((value) => value.name == name);
}

/// Why a file could not be imported.
enum BundleProblem {
  /// Not a zip, or a zip without this app's manifest.
  notAnExport,

  /// Written by a version of the app that knows more than this one.
  newerVersion,

  /// An export, but with entries missing or malformed.
  damaged,
}

class BundleException implements Exception {
  const BundleException(this.problem, [this.detail = '']);

  final BundleProblem problem;

  /// What was wrong, for logs. Not shown to the person.
  final String detail;

  @override
  String toString() => 'BundleException(${problem.name}: $detail)';
}

/// The fields of one JSON object, read with the type each must have.
class _Fields {
  _Fields(this._map, this._where);

  factory _Fields.of(Object? value, String where) {
    if (value is! Map<String, Object?>) {
      throw BundleException(BundleProblem.damaged, '$where is not an object');
    }
    return _Fields(value, where);
  }

  final Map<String, Object?> _map;
  final String _where;

  /// Ids end up in file names under the media folder, so only the characters
  /// of an id this app makes are let through.
  static final _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  /// Keys this app makes: letters only, never ending in `a`, below which no
  /// key could be placed.
  static final _sortKeyPattern = RegExp(r'^[a-z]{0,255}[b-z]$');

  Never _fail(String key, String expected) => throw BundleException(
    BundleProblem.damaged,
    '$key of $_where is not $expected',
  );

  String string(String key) {
    final value = _map[key];
    return value is String ? value : _fail(key, 'text');
  }

  String stringOr(String key, String fallback) {
    final value = _map[key];
    return value is String ? value : fallback;
  }

  String id(String key) {
    final value = string(key);
    return _idPattern.hasMatch(value) ? value : _fail(key, 'an id');
  }

  String sortKey(String key) {
    final value = string(key);
    return _sortKeyPattern.hasMatch(value) ? value : _fail(key, 'a sort key');
  }

  bool flag(String key) {
    final value = _map[key];
    return value is bool && value;
  }

  int integer(String key) {
    final value = _map[key];
    return value is int && value >= 0 ? value : _fail(key, 'a whole number');
  }

  DateTime time(String key) => timeOrNull(key) ?? _fail(key, 'a time');

  DateTime? timeOrNull(String key) {
    final value = _map[key];
    if (value == null) return null;
    if (value is! String) _fail(key, 'a time');
    final parsed = DateTime.tryParse(value) ?? _fail(key, 'a time');
    // Notes read from the database carry local times; so do these.
    return parsed.toLocal();
  }

  List<Object?> list(String key) {
    final value = _map[key];
    if (value == null) return const [];
    return value is List<Object?> ? value : _fail(key, 'a list');
  }

  _Fields? fieldsOrNull(String key) {
    final value = _map[key];
    return value == null ? null : _Fields.of(value, '$key of $_where');
  }
}
