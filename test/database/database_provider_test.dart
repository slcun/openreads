import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreads/core/constants/enums/enums.dart';
import 'package:openreads/database/database_provider.dart';
import 'package:openreads/model/book.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;
  late String databasePath;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    databaseDirectory = await Directory.systemTemp.createTemp('openreads_db_');
    databasePath = '${databaseDirectory.path}${Platform.pathSeparator}Books.db';

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return databaseDirectory.path;
        }
        return null;
      },
    );
  });

  tearDown(() async {
    await deleteDatabase(databasePath);
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await databaseDirectory.delete(recursive: true);
  });

  test('fresh books database stores custom ISBN provider identifiers', () async {
    final database = await DatabaseProvider().createDatabase();
    final book = Book(
      title: 'Provider-backed book',
      author: 'Openreads',
      status: BookStatus.forLater,
      providerName: 'Custom Catalog',
      sourceId: 'catalog-123',
      readings: [],
      dateAdded: DateTime(2026, 6, 20),
      dateModified: DateTime(2026, 6, 20),
    );

    await database.insert('booksTable', book.toJSON());

    final rows = await database.query('booksTable');
    expect(rows.single['provider_name'], 'Custom Catalog');
    expect(rows.single['source_id'], 'catalog-123');

    await database.close();
  });

  test('v8 books database migrates custom ISBN provider identifiers',
      () async {
    final legacyDatabase = await openDatabase(
      databasePath,
      version: 8,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE booksTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            subtitle TEXT,
            author TEXT,
            description TEXT,
            book_type TEXT,
            status INTEGER,
            rating INTEGER,
            favourite INTEGER,
            deleted INTEGER,
            start_date TEXT,
            finish_date TEXT,
            pages INTEGER,
            publication_year INTEGER,
            isbn TEXT,
            olid TEXT,
            tags TEXT,
            my_review TEXT,
            notes TEXT,
            has_cover INTEGER,
            blur_hash TEXT,
            reading_time INTEGER,
            readings TEXT,
            date_added TEXT,
            date_modified TEXT
          )
        ''');
      },
    );
    await legacyDatabase.close();

    final database = await DatabaseProvider().createDatabase();
    final columns = await database.rawQuery('PRAGMA table_info(booksTable)');
    final columnNames = columns.map((column) => column['name']);
    expect(columnNames, containsAll(['provider_name', 'source_id']));

    final book = Book(
      title: 'Migrated provider-backed book',
      author: 'Openreads',
      status: BookStatus.forLater,
      providerName: 'Custom Catalog',
      sourceId: 'catalog-456',
      readings: [],
      dateAdded: DateTime(2026, 6, 20),
      dateModified: DateTime(2026, 6, 20),
    );
    final id = await database.insert('booksTable', book.toJSON());
    await database.update(
      'booksTable',
      book.copyWith(sourceId: 'catalog-789').toJSON(),
      where: 'id = ?',
      whereArgs: [id],
    );

    final rows = await database.query('booksTable', where: 'id = ?', whereArgs: [id]);
    expect(rows.single['provider_name'], 'Custom Catalog');
    expect(rows.single['source_id'], 'catalog-789');

    await database.close();
  });
}
