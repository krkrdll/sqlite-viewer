import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/db_models.dart';
import '../services/database_service.dart';

/// テーブルスキーマの表示
class SchemaView extends StatefulWidget {
  final DatabaseService dbService;
  final String table;

  const SchemaView({
    super.key,
    required this.dbService,
    required this.table,
  });

  @override
  State<SchemaView> createState() => _SchemaViewState();
}

class _SchemaViewState extends State<SchemaView> {
  TableSchema? _schema;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final schema = await widget.dbService.getTableSchema(widget.table);
      if (!mounted) return;
      setState(() => _schema = schema);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text('エラー: $_error', style: const TextStyle(color: Colors.red)),
      );
    }
    final schema = _schema;
    if (schema == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('カラム', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 36,
              columns: const [
                DataColumn(label: Text('#')),
                DataColumn(label: Text('名前')),
                DataColumn(label: Text('型')),
                DataColumn(label: Text('NOT NULL')),
                DataColumn(label: Text('デフォルト')),
                DataColumn(label: Text('PK')),
              ],
              rows: schema.columns
                  .map((c) => DataRow(cells: [
                        DataCell(Text('${c.cid}')),
                        DataCell(Text(c.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600))),
                        DataCell(Text(c.type.isEmpty ? '—' : c.type)),
                        DataCell(c.notNull
                            ? const Icon(Icons.check, size: 16)
                            : const SizedBox.shrink()),
                        DataCell(Text(c.defaultValue ?? '—')),
                        DataCell(c.isPrimaryKey
                            ? const Icon(Icons.key,
                                size: 16, color: Colors.amber)
                            : const SizedBox.shrink()),
                      ]))
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('インデックス', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (schema.indexes.isEmpty)
          const Text('インデックスはありません', style: TextStyle(color: Colors.grey))
        else
          Card(
            child: Column(
              children: schema.indexes
                  .map((idx) => ListTile(
                        dense: true,
                        leading: Icon(
                          idx.unique ? Icons.fingerprint : Icons.sort,
                          size: 18,
                        ),
                        title: Text(idx.name),
                        subtitle: Text(
                          '${idx.unique ? 'UNIQUE — ' : ''}'
                          '${idx.columns.join(', ')}',
                        ),
                      ))
                  .toList(),
            ),
          ),
        const SizedBox(height: 24),
        Row(
          children: [
            Text('CREATE文', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              tooltip: 'コピー',
              onPressed: schema.createSql != null
                  ? () {
                      Clipboard.setData(
                          ClipboardData(text: schema.createSql!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('コピーしました')),
                      );
                    }
                  : null,
            ),
          ],
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              schema.createSql ?? '(なし)',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}
