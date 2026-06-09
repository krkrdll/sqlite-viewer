/// SQLiteで利用できる代表的なカラム型
const List<String> kSqliteColumnTypes = [
  'INTEGER',
  'TEXT',
  'REAL',
  'NUMERIC',
  'BLOB',
];

/// 新規テーブル作成時の1カラム分の定義（GUI入力用）
class NewColumnDef {
  String name;
  String type;
  bool primaryKey;
  bool autoIncrement;
  bool notNull;
  bool unique;
  String defaultValue;

  NewColumnDef({
    this.name = '',
    this.type = 'INTEGER',
    this.primaryKey = false,
    this.autoIncrement = false,
    this.notNull = false,
    this.unique = false,
    this.defaultValue = '',
  });
}

/// 識別子をダブルクォートでエスケープ
String quoteSqlIdentifier(String identifier) =>
    '"${identifier.replaceAll('"', '""')}"';

/// カラム定義から CREATE TABLE 文を組み立てる。
/// 主キーが複数指定された場合はテーブルレベルの制約として出力する。
String buildCreateTableSql(String tableName, List<NewColumnDef> columns) {
  final pkColumns = columns.where((c) => c.primaryKey).toList();
  final useInlinePk = pkColumns.length == 1;

  final defs = <String>[];
  for (final c in columns) {
    final buf = StringBuffer(quoteSqlIdentifier(c.name.trim()));
    if (c.type.trim().isNotEmpty) {
      buf.write(' ${c.type.trim()}');
    }
    if (useInlinePk && c.primaryKey) {
      buf.write(' PRIMARY KEY');
      if (c.autoIncrement) {
        buf.write(' AUTOINCREMENT');
      }
    }
    if (c.notNull) {
      buf.write(' NOT NULL');
    }
    if (c.unique) {
      buf.write(' UNIQUE');
    }
    if (c.defaultValue.trim().isNotEmpty) {
      buf.write(' DEFAULT ${c.defaultValue.trim()}');
    }
    defs.add(buf.toString());
  }

  if (pkColumns.length > 1) {
    final cols = pkColumns
        .map((c) => quoteSqlIdentifier(c.name.trim()))
        .join(', ');
    defs.add('PRIMARY KEY ($cols)');
  }

  return 'CREATE TABLE ${quoteSqlIdentifier(tableName.trim())} (\n'
      '  ${defs.join(',\n  ')}\n'
      ')';
}

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
