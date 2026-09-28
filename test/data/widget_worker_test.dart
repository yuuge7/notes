import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/home_widgets/widget_worker.dart';
import 'package:notes/data/repository/checklist_repository.dart';
import 'package:notes/data/repository/note_repository.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/note_type.dart';

import '../support/fake_home_widgets.dart';

/// A tick on a note widget, as the worker Android starts writes it: through
/// the app's own code, with a snapshot for the widgets after.
void main() {
  late Directory folder;
  late File file;
  late FakeHomeWidgets widgets;
  late WidgetWorker worker;

  /// A fresh connection to the same file each time, as the worker opens and
  /// closes one for each run.
  AppDatabase open() => AppDatabase(NativeDatabase(file));

  setUp(() {
    folder = Directory.systemTemp.createTempSync('notes_widget_worker_');
    file = File('${folder.path}/notes.sqlite');
    widgets = FakeHomeWidgets();
    worker = WidgetWorker(open, widgets);
  });

  tearDown(() => folder.deleteSync(recursive: true));

  Future<T> withDb<T>(Future<T> Function(AppDatabase db) use) async {
    final db = open();
    try {
      return await use(db);
    } finally {
      await db.close();
    }
  }

  /// A list of [texts], none checked.
  Future<Note> list(List<String> texts, {String title = 'Groceries'}) =>
      withDb((db) async {
        final notes = NoteRepository(db.noteDao);
        final lists = ChecklistRepository(db.noteDao);
        final note = await notes.create(type: NoteType.checklist, title: title);
        for (final text in texts) {
          await lists.add(note.id, text: text);
        }
        return (await notes.load(note.id))!;
      });

  Future<Note> reload(String id) =>
      withDb((db) async => (await NoteRepository(db.noteDao).load(id))!);

  Map<String, Object?> pageIn(Map<String, Object?> snapshot, String id) =>
      (snapshot['pages']! as Map<String, Object?>)[id]! as Map<String, Object?>;

  test('ticks an item off, and hands the widgets the list as it is', () async {
    final groceries = await list(['Oat milk', 'Eggs']);
    final eggs = groceries.items.last;
    widgets.show({groceries.id});

    await worker.setChecked(groceries.id, eggs.id, checked: true);

    expect((await reload(groceries.id)).checkedItems.single.text, 'Eggs');
    final page = pageIn(widgets.published.single, groceries.id);
    expect(
      [for (final item in page['done']! as List) (item as Map)['id']],
      [eggs.id],
    );
  });

  test('unticks one, back among the open items', () async {
    final groceries = await list(['Oat milk', 'Eggs']);
    final eggs = groceries.items.last;
    widgets.show({groceries.id});
    await worker.setChecked(groceries.id, eggs.id, checked: true);

    await worker.setChecked(groceries.id, eggs.id, checked: false);

    expect((await reload(groceries.id)).checkedItems, isEmpty);
    expect(pageIn(widgets.published.last, groceries.id)['done'], isEmpty);
  });

  test('taps made together are written in order, with one snapshot', () async {
    final groceries = await list(['Oat milk', 'Eggs', 'Rice']);
    final [milk, eggs, rice] = groceries.items;
    widgets.show({groceries.id});

    await Future.wait([
      worker.setChecked(groceries.id, milk.id, checked: true),
      worker.setChecked(groceries.id, eggs.id, checked: true),
      worker.setChecked(groceries.id, milk.id, checked: false),
      worker.setChecked(groceries.id, rice.id, checked: true),
    ]);

    expect(
      [for (final item in (await reload(groceries.id)).checkedItems) item.text],
      ['Eggs', 'Rice'],
    );
    expect(widgets.published, hasLength(1));
  });

  test('a tap after one lands runs again', () async {
    final groceries = await list(['Oat milk', 'Eggs']);
    final [milk, eggs] = groceries.items;

    await worker.setChecked(groceries.id, milk.id, checked: true);
    await worker.setChecked(groceries.id, eggs.id, checked: true);

    expect((await reload(groceries.id)).checkedItems, hasLength(2));
    expect(widgets.published, hasLength(2));
  });

  test('leaves a note in the trash as it was', () async {
    final groceries = await list(['Oat milk']);
    await withDb((db) => NoteRepository(db.noteDao).delete(groceries.id));

    await worker.setChecked(
      groceries.id,
      groceries.items.single.id,
      checked: true,
    );

    expect((await reload(groceries.id)).checkedItems, isEmpty);
    // The widget still hears that its note is gone.
    widgets.show({groceries.id});
    await worker.refresh();
    expect(
      (widgets.published.last['pages']! as Map<String, Object?>)[groceries.id],
      isNull,
    );
  });

  test('refresh hands over a note just chosen, wherever it is', () async {
    final groceries = await list(['Oat milk']);
    for (var i = 0; i < 25; i++) {
      await list(['Item $i'], title: 'Newer $i');
    }
    widgets.show({groceries.id});

    await worker.refresh();

    expect(
      pageIn(widgets.published.single, groceries.id)['title'],
      'Groceries',
    );
  });
}
