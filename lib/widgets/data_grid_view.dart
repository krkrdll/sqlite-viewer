import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/db_models.dart';
import '../services/database_service.dart';
import 'row_editor_dialog.dart';

/// テーブルデータの閲覧・編集グリッド
class DataGridView extends StatefulWidget {
  final DatabaseService dbService;
  final String table;
  final bool readOnly;

  const DataGridView({
    super.key,
    required this.dbService,
    required this.table,
    this.readOnly = false,
  });

  @override
  State<DataGridView> createState() => _DataGridViewState();
}

class _DataGridViewState extends State<DataGridView> {
  static const _pageSize = 100;

  TablePage? _page;
  TableSchema? _schema;
  int _offset = 0;
  String? _sortColumn;
  bool _sortDescending = false;
  bool _loading = true;
  String? _error;

  final _horizontalController = ScrollController();
  final _verticalController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final schema = await widget.dbService.getTableSchema(widget.table);
      final page = await widget.dbService.getTablePage(
        widget.table,
        offset: _offset,
        limit: _pageSize,
        orderBy: _sortColumn,
        descending: _sortDescending,
      );
      if (!mounted) return;
      setState(() {
        _schema = schema;
        _page = page;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _sort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortDescending = !_sortDescending;
      } else {
        _sortColumn = column;
        _sortDescending = false;
      }
      _offset = 0;
    });
    _load();
  }

  Future<void> _addRow() async {
    final schema = _schema;
    if (schema == null) return;
    final values = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => RowEditorDialog(columns: schema.columns),
    );
    if (values == null) return;
    try {
      // 空文字の整数PK（AUTOINCREMENT想定）は除外して自動採番させる
      final cleaned = Map<String, Object?>.from(values);
      for (final pk in schema.primaryKeys) {
        if (pk.type.toUpperCase().contains('INT') && cleaned[pk.name] == '') {
          cleaned.remove(pk.name);
        }
      }
      await widget.dbService.insertRow(widget.table, cleaned);
      await _load();
    } catch (e) {
      _showError('挿入に失敗しました: $e');
    }
  }

  Future<void> _editRow(Map<String, Object?> row) async {
    final schema = _schema;
    final rowId = row['_rowid_'] as int?;
    if (schema == null || rowId == null) {
      _showError('この行は編集できません（rowidがありません）');
      return;
    }
    final initial = {for (final c in schema.columns) c.name: row[c.name]};
    final values = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) =>
          RowEditorDialog(columns: schema.columns, initialValues: initial),
    );
    if (values == null) return;
    try {
      await widget.dbService.updateRowByRowId(widget.table, rowId, values);
      await _load();
    } catch (e) {
      _showError('更新に失敗しました: $e');
    }
  }

  Future<void> _deleteRow(Map<String, Object?> row) async {
    final rowId = row['_rowid_'] as int?;
    if (rowId == null) {
      _showError('この行は削除できません（rowidがありません）');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('行を削除'),
        content: const Text('この行を削除しますか？この操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.dbService.deleteRowByRowId(widget.table, rowId);
      await _load();
    } catch (e) {
      _showError('削除に失敗しました: $e');
    }
  }

  Future<void> _exportCsv() async {
    try {
      final csv = await widget.dbService.exportTableToCsv(widget.table);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'CSVとして保存',
        fileName: '${widget.table}.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (path == null) return;
      await widget.dbService.saveCsvFile(csv, path);
      _showMessage('CSVを保存しました: $path');
    } catch (e) {
      _showError('エクスポートに失敗しました: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text('エラー: $_error', style: const TextStyle(color: Colors.red)),
      );
    }
    final page = _page;
    if (page == null) return const SizedBox.shrink();

    return Column(
      children: [
        _buildToolbar(page),
        const Divider(height: 1),
        Expanded(
          child: page.rows.isEmpty
              ? const Center(child: Text('データがありません'))
              : _buildGrid(page),
        ),
      ],
    );
  }

  Widget _buildToolbar(TablePage page) {
    final from = page.totalCount == 0 ? 0 : _offset + 1;
    final to = (_offset + page.rows.length).clamp(0, page.totalCount);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          if (!widget.readOnly) ...[
            FilledButton.tonalIcon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('行を追加'),
              onPressed: _addRow,
            ),
            const SizedBox(width: 8),
          ],
          OutlinedButton.icon(
            icon: const Icon(Icons.download, size: 18),
            label: const Text('CSV'),
            onPressed: _exportCsv,
          ),
          const Spacer(),
          Text('$from–$to / ${page.totalCount} 件'),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: '前のページ',
            onPressed: _offset > 0
                ? () {
                    setState(
                      () => _offset = (_offset - _pageSize).clamp(
                        0,
                        page.totalCount,
                      ),
                    );
                    _load();
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: '次のページ',
            onPressed: _offset + _pageSize < page.totalCount
                ? () {
                    setState(() => _offset += _pageSize);
                    _load();
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(TablePage page) {
    final sortIndex = _sortColumn != null
        ? page.columns.indexOf(_sortColumn!)
        : -1;

    return LayoutBuilder(
      builder: (context, constraints) => Scrollbar(
        controller: _verticalController,
        thumbVisibility: true,
        child: Scrollbar(
          controller: _horizontalController,
          thumbVisibility: true,
          notificationPredicate: (notification) => notification.depth == 1,
          child: SingleChildScrollView(
            controller: _verticalController,
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  columnSpacing: 24,
                  sortColumnIndex: sortIndex >= 0 ? sortIndex : null,
                  sortAscending: !_sortDescending,
                  headingRowHeight: 40,
                  dataRowMinHeight: 32,
                  dataRowMaxHeight: 40,
                  columns: [
                    ...page.columns.map(
                      (c) => DataColumn(
                        label: Text(
                          c,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onSort: (_, _) => _sort(c),
                      ),
                    ),
                    if (!widget.readOnly) const DataColumn(label: Text('操作')),
                  ],
                  rows: page.rows.map((row) {
                    return DataRow(
                      cells: [
                        ...page.columns.map(
                          (c) => DataCell(_buildCell(row[c])),
                        ),
                        if (!widget.readOnly)
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 16),
                                  tooltip: '編集',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _editRow(row),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 16,
                                  ),
                                  tooltip: '削除',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _deleteRow(row),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCell(Object? value) {
    if (value == null) {
      return const Text(
        'NULL',
        style: TextStyle(
          color: Colors.grey,
          fontStyle: FontStyle.italic,
          fontSize: 13,
        ),
      );
    }
    var text = value.toString();
    if (text.length > 200) {
      text = '${text.substring(0, 200)}…';
    }
    return Tooltip(
      message: value.toString().length > 200 ? value.toString() : '',
      child: Text(
        text,
        style: const TextStyle(fontSize: 13),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
