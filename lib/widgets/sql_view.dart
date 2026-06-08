import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/db_models.dart';
import '../services/database_service.dart';

/// 任意のSQLを実行する画面
class SqlView extends StatefulWidget {
  final DatabaseService dbService;
  final VoidCallback? onSchemaChanged;

  const SqlView({
    super.key,
    required this.dbService,
    this.onSchemaChanged,
  });

  @override
  State<SqlView> createState() => _SqlViewState();
}

class _SqlViewState extends State<SqlView>
    with AutomaticKeepAliveClientMixin {
  final _controller = TextEditingController();
  QueryResult? _result;
  String? _error;
  bool _running = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _execute() async {
    final sql = _controller.text.trim();
    if (sql.isEmpty) return;

    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final result = await widget.dbService.executeSql(sql);
      if (!mounted) return;
      setState(() {
        _result = result;
        _running = false;
      });
      // DDLの可能性があるのでテーブル一覧を更新
      final lower = sql.toLowerCase();
      if (lower.contains('create') ||
          lower.contains('drop') ||
          lower.contains('alter')) {
        widget.onSchemaChanged?.call();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _result = null;
        _running = false;
      });
    }
  }

  Future<void> _exportCsv() async {
    final result = _result;
    if (result == null || !result.isSelect) return;
    try {
      final csv = widget.dbService.exportResultToCsv(result);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'CSVとして保存',
        fileName: 'query_result.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (path == null) return;
      await widget.dbService.saveCsvFile(csv, path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSVを保存しました: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('エクスポートに失敗しました: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _controller,
            maxLines: 6,
            minLines: 3,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'SELECT * FROM table_name LIMIT 100;',
              labelText: 'SQL',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              FilledButton.icon(
                icon: _running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow, size: 18),
                label: const Text('実行'),
                onPressed: _running ? null : _execute,
              ),
              const SizedBox(width: 8),
              if (_result != null && _result!.isSelect)
                OutlinedButton.icon(
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('CSV'),
                  onPressed: _exportCsv,
                ),
              const Spacer(),
              if (_result != null)
                Text(
                  _result!.isSelect
                      ? '${_result!.rows.length} 行 '
                          '(${_result!.elapsed.inMilliseconds} ms)'
                      : '${_result!.affectedRows} 行に影響 '
                          '(${_result!.elapsed.inMilliseconds} ms)',
                  style: const TextStyle(color: Colors.grey),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        Expanded(child: _buildResult()),
      ],
    );
  }

  Widget _buildResult() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          _error!,
          style: const TextStyle(color: Colors.red, fontFamily: 'monospace'),
        ),
      );
    }
    final result = _result;
    if (result == null) {
      return const Center(
        child: Text('SQLを入力して実行してください',
            style: TextStyle(color: Colors.grey)),
      );
    }
    if (!result.isSelect) {
      return Center(
        child: Text('${result.affectedRows} 行に影響しました',
            style: const TextStyle(fontSize: 16)),
      );
    }
    if (result.rows.isEmpty) {
      return const Center(child: Text('結果は0件です'));
    }

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              headingRowHeight: 40,
          dataRowMinHeight: 32,
          dataRowMaxHeight: 40,
          columns: result.columns
              .map((c) => DataColumn(
                    label: Text(c,
                        style:
                            const TextStyle(fontWeight: FontWeight.bold)),
                  ))
              .toList(),
          rows: result.rows
              .map((row) => DataRow(
                    cells: result.columns
                        .map((c) => DataCell(_buildCell(row[c])))
                        .toList(),
                  ))
              .toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCell(Object? value) {
    if (value == null) {
      return const Text('NULL',
          style: TextStyle(
              color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 13));
    }
    var text = value.toString();
    if (text.length > 200) {
      text = '${text.substring(0, 200)}…';
    }
    return Text(text,
        style: const TextStyle(fontSize: 13),
        overflow: TextOverflow.ellipsis);
  }
}
