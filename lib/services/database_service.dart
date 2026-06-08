import 'dart:io';

import 'package:csv/csv.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/db_models.dart';

/// SQLiteデータベースへのアクセスを担うサービス
class DatabaseService {
  Database? _db;
  String? _path;

  bool get isOpen => _db != null;
  String? get path => _path;

  /// データベースファイルを開く
  Future<void> open(String filePath) async {
    await close();
    _db = await databaseFactoryFfi.openDatabase(filePath);
    _path = filePath;
  }

  /// 新規データベースファイルを作成して開く。
  /// 既存ファイルがある場合、overwriteがtrueなら削除して作り直す。
  Future<void> create(String filePath, {bool overwrite = false}) async {
    await close();
    final file = File(filePath);
    if (await file.exists()) {
      if (!overwrite) {
        throw StateError('ファイルが既に存在します: $filePath');
      }
      await file.delete();
    }
    _db = await databaseFactoryFfi.openDatabase(filePath);
    _path = filePath;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _path = null;
  }

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('データベースが開かれていません');
    }
    return db;
  }

  /// テーブル名の一覧（sqlite内部テーブルは除外）
  Future<List<String>> getTableNames() async {
    final rows = await _database.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  /// ビュー名の一覧
  Future<List<String>> getViewNames() async {
    final rows = await _database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'view' ORDER BY name",
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  /// テーブルのスキーマ情報を取得
  Future<TableSchema> getTableSchema(String table) async {
    final colRows = await _database.rawQuery(
      'PRAGMA table_info(${_quote(table)})',
    );
    final columns = colRows.map(ColumnInfo.fromMap).toList();

    final idxRows = await _database.rawQuery(
      'PRAGMA index_list(${_quote(table)})',
    );
    final indexes = <IndexInfo>[];
    for (final idx in idxRows) {
      final idxName = idx['name'] as String;
      final infoRows = await _database.rawQuery(
        'PRAGMA index_info(${_quote(idxName)})',
      );
      indexes.add(
        IndexInfo(
          name: idxName,
          unique: (idx['unique'] as int? ?? 0) != 0,
          columns: infoRows
              .map((r) => (r['name'] as String?) ?? '(expr)')
              .toList(),
        ),
      );
    }

    final sqlRows = await _database.rawQuery(
      "SELECT sql FROM sqlite_master WHERE name = ?",
      [table],
    );
    final createSql = sqlRows.isNotEmpty
        ? sqlRows.first['sql'] as String?
        : null;

    return TableSchema(
      name: table,
      columns: columns,
      indexes: indexes,
      createSql: createSql,
    );
  }

  /// テーブルデータをページ取得
  Future<TablePage> getTablePage(
    String table, {
    required int offset,
    required int limit,
    String? orderBy,
    bool descending = false,
  }) async {
    final countRows = await _database.rawQuery(
      'SELECT COUNT(*) AS cnt FROM ${_quote(table)}',
    );
    final total = countRows.first['cnt'] as int;

    final order = orderBy != null
        ? 'ORDER BY ${_quote(orderBy)} ${descending ? 'DESC' : 'ASC'}'
        : '';

    // ビューやWITHOUT ROWIDテーブルにはrowidがないためフォールバックする
    List<Map<String, Object?>> data;
    try {
      data = await _database.rawQuery(
        'SELECT rowid AS _rowid_, * FROM ${_quote(table)} $order '
        'LIMIT $limit OFFSET $offset',
      );
    } catch (_) {
      data = await _database.rawQuery(
        'SELECT * FROM ${_quote(table)} $order LIMIT $limit OFFSET $offset',
      );
    }

    final schema = await getTableSchema(table);
    return TablePage(
      columns: schema.columns.map((c) => c.name).toList(),
      rows: data,
      totalCount: total,
    );
  }

  /// 行を挿入
  Future<void> insertRow(String table, Map<String, Object?> values) async {
    await _database.insert(table, values);
  }

  /// rowidを指定して行を更新
  Future<void> updateRowByRowId(
    String table,
    int rowId,
    Map<String, Object?> values,
  ) async {
    await _database.update(
      table,
      values,
      where: 'rowid = ?',
      whereArgs: [rowId],
    );
  }

  /// rowidを指定して行を削除
  Future<void> deleteRowByRowId(String table, int rowId) async {
    await _database.delete(table, where: 'rowid = ?', whereArgs: [rowId]);
  }

  /// 任意のSQLを実行する。SELECT系は結果を、更新系は影響行数を返す
  Future<QueryResult> executeSql(String sql) async {
    final stopwatch = Stopwatch()..start();
    final trimmed = sql.trim().toLowerCase();
    final isQuery =
        trimmed.startsWith('select') ||
        trimmed.startsWith('pragma') ||
        trimmed.startsWith('with') ||
        trimmed.startsWith('explain');

    if (isQuery) {
      final rows = await _database.rawQuery(sql);
      stopwatch.stop();
      final columns = rows.isNotEmpty ? rows.first.keys.toList() : <String>[];
      return QueryResult(
        columns: columns,
        rows: rows,
        elapsed: stopwatch.elapsed,
      );
    } else {
      final count = await _database.rawUpdate(sql);
      stopwatch.stop();
      return QueryResult(
        columns: const [],
        rows: const [],
        affectedRows: count,
        elapsed: stopwatch.elapsed,
      );
    }
  }

  /// テーブル全体をCSV文字列に変換
  Future<String> exportTableToCsv(String table) async {
    final rows = await _database.rawQuery('SELECT * FROM ${_quote(table)}');
    return _toCsv(rows);
  }

  /// クエリ結果をCSV文字列に変換
  String exportResultToCsv(QueryResult result) {
    final maps = result.rows
        .map((r) => {for (final c in result.columns) c: r[c]})
        .toList();
    return _toCsv(maps, columns: result.columns);
  }

  /// CSV文字列をファイルに保存
  Future<void> saveCsvFile(String csvContent, String filePath) async {
    // ExcelでUTF-8を正しく認識させるためBOMを付与
    const bom = '\u{FEFF}';
    await File(filePath).writeAsString('$bom$csvContent');
  }

  String _toCsv(List<Map<String, Object?>> rows, {List<String>? columns}) {
    if (rows.isEmpty && (columns == null || columns.isEmpty)) {
      return '';
    }
    final cols = columns ?? rows.first.keys.toList();
    final data = <List<Object?>>[
      cols,
      ...rows.map((r) => cols.map((c) => r[c]).toList()),
    ];
    return const ListToCsvConverter().convert(data);
  }

  /// 識別子をダブルクォートでエスケープ
  String _quote(String identifier) => '"${identifier.replaceAll('"', '""')}"';
}
