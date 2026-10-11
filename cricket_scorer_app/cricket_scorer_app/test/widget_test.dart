import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cricket_scorer_app/main.dart';

void main() {
  testWidgets('60Score boots to splash with credit', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const Score60App());
    await tester.pump();
    expect(find.text('60Score'), findsOneWidget);
    expect(find.text('Made by Sharjeel'), findsOneWidget);
    // Let the splash timer finish and the welcome dialog appear.
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    expect(find.text('Welcome to 60Score'), findsOneWidget);
    await tester.tap(find.text('Fresh Start'));
    await tester.pumpAndSettle();
    expect(find.text('Registration'), findsWidgets);
    expect(find.text('Scorer'), findsWidgets);
  });
}
