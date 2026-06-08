import 'package:flutter_test/flutter_test.dart';

import 'package:sqlite_viewer/main.dart';

void main() {
  testWidgets('起動時にウェルカム画面が表示される', (WidgetTester tester) async {
    await tester.pumpWidget(const SqliteViewerApp());

    expect(find.text('SQLiteデータベースファイルを開いてください'), findsOneWidget);
    expect(find.text('データベースを開く'), findsOneWidget);
  });
}
