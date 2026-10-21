// Tournament list card layout (v1.3.2, bug #R2): with a Published
// badge and all three action buttons present, a long tournament
// name was squeezed to one letter per line. The card now gives the
// name its own title line (2 lines max, ellipsis), moves the badge
// to the subtitle row, and uses compact action buttons.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/screens/tournaments_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void narrow320(WidgetTester tester) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
  }

  Tournament longNamed({bool published = true}) => Tournament(
        id: 't1',
        name: 'Super Sixty League Season 2K26 Grand Championship',
        teamIds: const ['a', 'b', 'c', 'd', 'e', 'f'],
        venue: '75 LOKRI CLUB',
        published: published,
      );

  Widget host(Tournament t, {bool loggedIn = true}) => MaterialApp(
        home: Scaffold(
          body: TournamentCard(
            tournament: t,
            teamCount: t.teamIds.length,
            matchCount: 18,
            loggedIn: loggedIn,
            onTap: () {},
            onTogglePublish: () {},
            onEdit: () {},
            onDelete: () {},
          ),
        ),
      );

  testWidgets(
      'long name + Published badge + all actions fit 320dp with no '
      'overflow and no letter-per-line title', (tester) async {
    narrow320(tester);
    final t = longNamed();
    await tester.pumpWidget(host(t));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Published'), findsOneWidget);
    expect(find.byIcon(Icons.public), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    // The title is capped at two lines with an ellipsis…
    final title = tester.widget<Text>(find.text(t.name));
    expect(title.maxLines, 2);
    expect(title.overflow, TextOverflow.ellipsis);
    // …and it renders with real width (a letter-per-line title would
    // be a few pixels wide and many lines tall).
    final size = tester.getSize(find.text(t.name));
    expect(size.width, greaterThan(50));
    expect(size.height, lessThan(64));
  });

  testWidgets('unpublished + logged out: no badge, no publish action',
      (tester) async {
    narrow320(tester);
    final t = longNamed(published: false);
    await tester.pumpWidget(host(t, loggedIn: false));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Published'), findsNothing);
    expect(find.byIcon(Icons.public), findsNothing);
    expect(find.byIcon(Icons.public_off), findsNothing);
    expect(find.byIcon(Icons.edit), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });
}
