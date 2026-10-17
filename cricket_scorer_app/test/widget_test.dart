import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cricket_scorer_app/main.dart';

void main() {
  testWidgets('60Score boots to splash then home', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const Score60App());
    await tester.pump();
    // Splash shows the embedded logo artwork.
    expect(find.byType(Image), findsWidgets);
    // Let the splash timer finish and the home dashboard appear.
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pumpAndSettle();
    // Home dashboard: featured tournament + bottom nav.
    expect(find.textContaining('Super Sixty League'), findsWidgets);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Matches'), findsWidgets);
  });
}
