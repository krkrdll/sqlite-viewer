import 'package:flutter/material.dart';

import '../models/db_models.dart';

/// 新規テーブルをGUIで定義するダイアログ。
/// 保存に成功すると作成したテーブル名を返す。
class CreateTableDialog extends StatefulWidget {
  /// 既存のテーブル・ビュー名（重複チェック用）
  final List<String> existingNames;

  /// 実際にテーブルを作成する処理
  final Future<void> Function(String tableName, List<NewColumnDef> columns)
  onCreate;

  const CreateTableDialog({
    super.key,
    required this.existingNames,
    required this.onCreate,
  });

  @override
  State<CreateTableDialog> createState() => _CreateTableDialogState();
}

class _CreateTableDialogState extends State<CreateTableDialog> {
  final _tableNameController = TextEditingController();
  final List<NewColumnDef> _columns = [
    NewColumnDef(name: 'id', primaryKey: true, autoIncrement: true),
  ];
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tableNameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tableNameController.dispose();
    super.dispose();
  }

  void _addColumn() {
    setState(() => _columns.add(NewColumnDef()));
  }

  void _removeColumn(int index) {
    setState(() => _columns.removeAt(index));
  }

  /// 入力内容を検証。問題なければnullを返す。
  String? _validate() {
    final name = _tableNameController.text.trim();
    if (name.isEmpty) {
      return 'テーブル名を入力してください';
    }
    if (widget.existingNames.contains(name)) {
      return '同名のテーブル/ビューが既に存在します: $name';
    }
    if (_columns.isEmpty) {
      return 'カラムを1つ以上定義してください';
    }
    final seen = <String>{};
    for (final c in _columns) {
      final cn = c.name.trim();
      if (cn.isEmpty) {
        return 'カラム名が空の項目があります';
      }
      if (!seen.add(cn.toLowerCase())) {
        return 'カラム名が重複しています: $cn';
      }
    }
    final pkCount = _columns.where((c) => c.primaryKey).length;
    if (pkCount > 1 && _columns.any((c) => c.primaryKey && c.autoIncrement)) {
      return 'AUTOINCREMENTは単一の主キーにのみ指定できます';
    }
    return null;
  }

  Future<void> _save() async {
    final validationError = _validate();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await widget.onCreate(_tableNameController.text.trim(), _columns);
      if (mounted) {
        Navigator.of(context).pop(_tableNameController.text.trim());
      }
    } catch (e) {
      setState(() {
        _error = 'テーブル作成に失敗しました: $e';
        _saving = false;
      });
    }
  }

  String get _previewSql {
    final name = _tableNameController.text.trim();
    if (name.isEmpty || _columns.any((c) => c.name.trim().isEmpty)) {
      return '-- テーブル名とカラム名を入力するとプレビューが表示されます';
    }
    return buildCreateTableSql(name, _columns);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('テーブルを新規作成'),
      content: SizedBox(
        width: 720,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _tableNameController,
              decoration: const InputDecoration(
                labelText: 'テーブル名',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('カラム定義', style: theme.textTheme.titleSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addColumn,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('カラム追加'),
                ),
              ],
            ),
            const _ColumnHeaderRow(),
            const Divider(height: 8),
            Expanded(
              child: _columns.isEmpty
                  ? const Center(child: Text('カラムがありません'))
                  : ListView.builder(
                      itemCount: _columns.length,
                      itemBuilder: (context, index) => _ColumnRow(
                        key: ValueKey(_columns[index]),
                        column: _columns[index],
                        onChanged: () => setState(() {}),
                        onRemove: () => _removeColumn(index),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Text('SQLプレビュー', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              height: 96,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _previewSql,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('作成'),
        ),
      ],
    );
  }
}

/// カラム一覧のヘッダー行
class _ColumnHeaderRow extends StatelessWidget {
  const _ColumnHeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('カラム名', style: style)),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: Text('型', style: style)),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: Text('デフォルト', style: style)),
          const SizedBox(width: 8),
          SizedBox(width: 40, child: Text('PK', style: style)),
          SizedBox(width: 48, child: Text('AI', style: style)),
          SizedBox(width: 56, child: Text('NN', style: style)),
          SizedBox(width: 56, child: Text('UQ', style: style)),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

/// カラム1行分の入力UI
class _ColumnRow extends StatefulWidget {
  final NewColumnDef column;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _ColumnRow({
    super.key,
    required this.column,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_ColumnRow> createState() => _ColumnRowState();
}

class _ColumnRowState extends State<_ColumnRow> {
  late final TextEditingController _nameController;
  late final TextEditingController _defaultController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.column.name);
    _defaultController = TextEditingController(text: widget.column.defaultValue);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _defaultController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final col = widget.column;
    final canAutoIncrement = col.primaryKey && col.type == 'INTEGER';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
              ),
              onChanged: (v) {
                col.name = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              initialValue: kSqliteColumnTypes.contains(col.type)
                  ? col.type
                  : kSqliteColumnTypes.first,
              isDense: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
              ),
              items: kSqliteColumnTypes
                  .map(
                    (t) => DropdownMenuItem(value: t, child: Text(t)),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                col.type = v;
                if (col.type != 'INTEGER') col.autoIncrement = false;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _defaultController,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: "例 0, 'text'",
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
              ),
              onChanged: (v) {
                col.defaultValue = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: Checkbox(
              value: col.primaryKey,
              onChanged: (v) {
                col.primaryKey = v ?? false;
                if (!col.primaryKey) col.autoIncrement = false;
                widget.onChanged();
              },
            ),
          ),
          SizedBox(
            width: 48,
            child: Tooltip(
              message: 'AUTOINCREMENT (INTEGERの主キーのみ)',
              child: Checkbox(
                value: col.autoIncrement,
                onChanged: canAutoIncrement
                    ? (v) {
                        col.autoIncrement = v ?? false;
                        widget.onChanged();
                      }
                    : null,
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: Tooltip(
              message: 'NOT NULL',
              child: Checkbox(
                value: col.notNull,
                onChanged: (v) {
                  col.notNull = v ?? false;
                  widget.onChanged();
                },
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: Tooltip(
              message: 'UNIQUE',
              child: Checkbox(
                value: col.unique,
                onChanged: (v) {
                  col.unique = v ?? false;
                  widget.onChanged();
                },
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: 'このカラムを削除',
              onPressed: widget.onRemove,
            ),
          ),
        ],
      ),
    );
  }
}
