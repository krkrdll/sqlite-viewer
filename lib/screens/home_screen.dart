import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

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
    final dbName = _dbService.path != null ? p.basename(_dbService.path!) : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(dbName != null ? 'SQLite Viewer — $dbName' : 'SQLite Viewer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'データベースを開く',
            onPressed: _openDatabase,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'テーブル一覧を更新',
            onPressed: _dbService.isOpen ? _refreshTables : null,
          ),
        ],
        bottom: _dbService.isOpen
            ? TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.table_rows), text: 'データ'),
                  Tab(icon: Icon(Icons.schema), text: 'スキーマ'),
                  Tab(icon: Icon(Icons.code), text: 'SQL'),
                ],
              )
            : null,
      ),
      body: _loading
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
                ),
    );
  }

  Widget _buildWelcome() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.storage, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text('SQLiteデータベースファイルを開いてください',
              style: TextStyle(fontSize: 16)),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.folder_open),
            label: const Text('データベースを開く'),
            onPressed: _openDatabase,
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
              child: Text('テーブル',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
          ..._tables.map((t) => _buildItemTile(
                name: t,
                icon: Icons.table_chart,
              )),
          if (_views.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('ビュー',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
          ..._views.map((v) => _buildItemTile(
                name: v,
                icon: Icons.visibility,
              )),
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
        leading: Icon(icon,
            size: 18,
            color: selected ? colorScheme.onPrimary : null),
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
