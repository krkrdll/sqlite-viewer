/// テーブルのカラム定義（PRAGMA table_info の結果）
class ColumnInfo {
  final int cid;
  final String name;
  final String type;
  final bool notNull;
  final String? defaultValue;
  final bool isPrimaryKey;

  const ColumnInfo({
    required this.cid,
    required this.name,
    required this.type,
    required this.notNull,
    required this.defaultValue,
    required this.isPrimaryKey,
  });

  factory ColumnInfo.fromMap(Map<String, Object?> map) => ColumnInfo(
    cid: map['cid'] as int,
    name: map['name'] as String,
    type: (map['type'] as String?) ?? '',
    notNull: (map['notnull'] as int? ?? 0) != 0,
    defaultValue: map['dflt_value']?.toString(),
    isPrimaryKey: (map['pk'] as int? ?? 0) != 0,
  );
}

/// インデックス定義
class IndexInfo {
  final String name;
  final bool unique;
  final List<String> columns;

  const IndexInfo({
    required this.name,
    required this.unique,
    required this.columns,
  });
}

/// テーブルのスキーマ情報
class TableSchema {
  final String name;
  final List<ColumnInfo> columns;
  final List<IndexInfo> indexes;
  final String? createSql;

  const TableSchema({
    required this.name,
    required this.columns,
    required this.indexes,
    required this.createSql,
  });

  List<ColumnInfo> get primaryKeys =>
      columns.where((c) => c.isPrimaryKey).toList();
}

/// クエリ結果（SELECT等）
class QueryResult {
  final List<String> columns;
  final List<Map<String, Object?>> rows;
  final int? affectedRows; // 更新系の場合
  final Duration elapsed;

  const QueryResult({
    required this.columns,
    required this.rows,
    this.affectedRows,
    required this.elapsed,
  });

  bool get isSelect => affectedRows == null;
}

/// テーブルデータのページ
class TablePage {
  final List<String> columns;
  final List<Map<String, Object?>> rows;
  final int totalCount;

  const TablePage({
    required this.columns,
    required this.rows,
    required this.totalCount,
  });
}
