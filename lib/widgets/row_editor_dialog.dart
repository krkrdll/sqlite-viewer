import 'package:flutter/material.dart';

import '../models/db_models.dart';

/// 行の追加・編集用ダイアログ。
/// 保存時に「カラム名 → 値」のマップを返す。NULLはnull、それ以外は文字列。
class RowEditorDialog extends StatefulWidget {
  final List<ColumnInfo> columns;
  final Map<String, Object?>? initialValues; // nullなら新規追加

  const RowEditorDialog({
    super.key,
    required this.columns,
    this.initialValues,
  });

  @override
  State<RowEditorDialog> createState() => _RowEditorDialogState();
}

class _RowEditorDialogState extends State<RowEditorDialog> {
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, bool> _isNull;

  bool get _isEdit => widget.initialValues != null;

  @override
  void initState() {
    super.initState();
    _controllers = {};
    _isNull = {};
    for (final col in widget.columns) {
      final value =
          widget.initialValues != null ? widget.initialValues![col.name] : null;
      _controllers[col.name] =
          TextEditingController(text: value?.toString() ?? '');
      _isNull[col.name] = _isEdit ? value == null : !col.notNull;
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final values = <String, Object?>{};
    for (final col in widget.columns) {
      if (_isNull[col.name]!) {
        values[col.name] = null;
      } else {
        values[col.name] = _parseValue(col, _controllers[col.name]!.text);
      }
    }
    Navigator.of(context).pop(values);
  }

  /// カラム型に応じて文字列を変換（SQLiteの型親和性に準拠）
  Object? _parseValue(ColumnInfo col, String text) {
    final type = col.type.toUpperCase();
    if (type.contains('INT')) {
      return int.tryParse(text) ?? text;
    }
    if (type.contains('REAL') ||
        type.contains('FLOA') ||
        type.contains('DOUB') ||
        type.contains('NUM') ||
        type.contains('DEC')) {
      return num.tryParse(text) ?? text;
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? '行を編集' : '行を追加'),
      content: SizedBox(
        width: 480,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: widget.columns.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final col = widget.columns[index];
            final isNull = _isNull[col.name]!;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controllers[col.name],
                    enabled: !isNull,
                    decoration: InputDecoration(
                      labelText:
                          '${col.name} (${col.type.isEmpty ? 'ANY' : col.type})'
                          '${col.isPrimaryKey ? ' 🔑' : ''}',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      hintText: isNull ? 'NULL' : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'NULLにする',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: isNull,
                        onChanged: col.notNull
                            ? null
                            : (v) =>
                                setState(() => _isNull[col.name] = v ?? false),
                      ),
                      const Text('NULL', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
