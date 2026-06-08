import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../services/database_service.dart';
import '../widgets/data_grid_view.dart';
import '../widgets/schema_view.dart';
import '../widgets/sql_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _dbService = DatabaseService();
  late final TabController _tabController;

  List<String> _tables = [];
  List<String> _views = [];
  String? _selectedTable;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _dbService.close();
    super.dispose();
  }

  Future<void> _openDatabase() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'SQLiteデータベースを開く',
      type: FileType.any,
    );
    final path = result?.files.single.path;
    if (path == null) return;

    setState(() => _loading = true);
    try {
      await _dbService.open(path);
      final tables = await _dbService.getTableNames();
      final views = await _dbService.getViewNames();
      setState(() {
        _tables = tables;
        _views = views;
        _selectedTable = tables.isNotEmpty ? tables.first : null;
      });
    } catch (e) {
      _showError('データベースを開けませんでした: $e');
      await _dbService.close();
      setState(() {
        _tables = [];
        _views = [];
        _selectedTable = null;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _createDatabase() async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '新規データベースを作成',
      fileName: 'new_database.db',
      type: FileType.custom,
      allowedExtensions: ['db', 'sqlite', 'sqlite3'],
    );
    if (path == null || !mounted) return;

    // 既存ファイルがある場合は上書き確認
    var overwrite = false;
    if (File(path).existsSync()) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('上書き確認'),
          content: Text(
            '${p.basename(path)} は既に存在します。'
            '削除して新規作成しますか？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('上書き'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      overwrite = true;
    }

    setState(() => _loading = true);
    try {
      await _dbService.create(path, overwrite: overwrite);
      setState(() {
        _tables = [];
        _views = [];
        _selectedTable = null;
      });
      // 空のDBなのでSQLタブを開いてテーブル作成を促す
      _tabController.animateTo(2);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'データベースを作成しました。'
              'SQLタブでCREATE TABLE文を実行してテーブルを作成できます。',
            ),
          ),
        );
      }
    } catch (e) {
      _showError('データベースの作成に失敗しました: $e');
      await _dbService.close();
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _refreshTables() async {
    if (!_dbService.isOpen) return;
    try {
      final tables = await _dbService.getTableNames();
      final views = await _dbService.getViewNames();
      setState(() {
        _tables = tables;
        _views = views;
        if (_selectedTable != null &&
            !tables.contains(_selectedTable) &&
            !views.contains(_selectedTable)) {
          _selectedTable = tables.isNotEmpty ? tables.first : null;
        }
      });
    } catch (e) {
      _showError('テーブル一覧の更新に失敗しました: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dbName = _dbService.path != null
        ? p.basename(_dbService.path!)
        : null;

    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              _createDatabase,
          const SingleActivator(LogicalKeyboardKey.keyO, control: true):
              _openDatabase,
          const SingleActivator(LogicalKeyboardKey.f5): _refreshTables,
        },
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              _buildMenuBar(dbName),
              if (_dbService.isOpen)
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: TabBar(
                    controller: _tabController,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.grey,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    tabs: const [
                      Tab(
                        child: _TabLabel(icon: Icons.table_rows, text: 'データ'),
                      ),
                      Tab(
                        child: _TabLabel(icon: Icons.schema, text: 'スキーマ'),
                      ),
                      Tab(
                        child: _TabLabel(icon: Icons.code, text: 'SQL'),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 1),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : !_dbService.isOpen
        ? _buildWelcome()
        : Row(
            children: [
              _buildSidebar(),
              const VerticalDivider(width: 1),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _selectedTable != null
                        ? DataGridView(
                            key: ValueKey('data-$_selectedTable'),
                            dbService: _dbService,
                            table: _selectedTable!,
                            readOnly: _views.contains(_selectedTable),
                          )
                        : const Center(child: Text('テーブルを選択してください')),
                    _selectedTable != null
                        ? SchemaView(
                            key: ValueKey('schema-$_selectedTable'),
                            dbService: _dbService,
                            table: _selectedTable!,
                          )
                        : const Center(child: Text('テーブルを選択してください')),
                    SqlView(
                      dbService: _dbService,
                      onSchemaChanged: _refreshTables,
                    ),
                  ],
                ),
              ),
            ],
          );
  }

  Widget _buildMenuBar(String? dbName) {
    final isOpen = _dbService.isOpen;
    return Row(
      children: [
        Expanded(
          child: MenuBar(
            style: const MenuStyle(elevation: WidgetStatePropertyAll(0)),
            children: [
              SubmenuButton(
                menuChildren: [
                  MenuItemButton(
                    onPressed: _createDatabase,
                    shortcut: const SingleActivator(
                      LogicalKeyboardKey.keyN,
                      control: true,
                    ),
                    leadingIcon: const Icon(Icons.note_add, size: 18),
                    child: const Text('新規作成...'),
                  ),
                  MenuItemButton(
                    onPressed: _openDatabase,
                    shortcut: const SingleActivator(
                      LogicalKeyboardKey.keyO,
                      control: true,
                    ),
                    leadingIcon: const Icon(Icons.folder_open, size: 18),
                    child: const Text('開く...'),
                  ),
                  const Divider(height: 1),
                  MenuItemButton(
                    onPressed: isOpen ? _closeDatabase : null,
                    leadingIcon: const Icon(Icons.close, size: 18),
                    child: const Text('閉じる'),
                  ),
                  const Divider(height: 1),
                  MenuItemButton(
                    onPressed: () => windowManager.close(),
                    leadingIcon: const Icon(Icons.exit_to_app, size: 18),
                    child: const Text('終了'),
                  ),
                ],
                child: const Text('ファイル'),
              ),
              SubmenuButton(
                menuChildren: [
                  MenuItemButton(
                    onPressed: isOpen ? _refreshTables : null,
                    shortcut: const SingleActivator(LogicalKeyboardKey.f5),
                    leadingIcon: const Icon(Icons.refresh, size: 18),
                    child: const Text('テーブル一覧を更新'),
                  ),
                ],
                child: const Text('表示'),
              ),
              SubmenuButton(
                menuChildren: [
                  MenuItemButton(
                    onPressed: _showAbout,
                    leadingIcon: const Icon(Icons.info_outline, size: 18),
                    child: const Text('バージョン情報'),
                  ),
                ],
                child: const Text('ヘルプ'),
              ),
            ],
          ),
        ),
        if (dbName != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              dbName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _closeDatabase() async {
    await _dbService.close();
    setState(() {
      _tables = [];
      _views = [];
      _selectedTable = null;
    });
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'SQLite Viewer',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.storage, size: 48),
      children: [const Text('SQLiteデータベースの閲覧・編集ツール')],
    );
  }

  Widget _buildWelcome() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.storage, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'SQLiteデータベースファイルを開いてください',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('データベースを開く'),
                onPressed: _openDatabase,
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.note_add),
                label: const Text('新規作成'),
                onPressed: _createDatabase,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return SizedBox(
      width: 240,
      child: ListView(
        children: [
          if (_tables.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'テーブル',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
          ..._tables.map(
            (t) => _buildItemTile(name: t, icon: Icons.table_chart),
          ),
          if (_views.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'ビュー',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
          ..._views.map((v) => _buildItemTile(name: v, icon: Icons.visibility)),
        ],
      ),
    );
  }

  Widget _buildItemTile({required String name, required IconData icon}) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = name == _selectedTable;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(
          icon,
          size: 18,
          color: selected ? colorScheme.onPrimary : null,
        ),
        title: Text(
          name,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? colorScheme.onPrimary : null,
            fontWeight: selected ? FontWeight.bold : null,
          ),
        ),
        selected: selected,
        selectedTileColor: colorScheme.primary,
        onTap: () => setState(() => _selectedTable = name),
      ),
    );
  }
}

/// アイコンとテキストを横並びにしたタブラベル
class _TabLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TabLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(text)],
    );
  }
}
