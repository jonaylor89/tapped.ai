import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intheloopapp/main.dart' as app;
import 'package:intheloopapp/ui/login/login_view.dart';
import 'package:intheloopapp/ui/splash/splash_view.dart';

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('timed out waiting for $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app finishes initialising and can navigate to login',
      (tester) async {
    await app.main();

    await pumpUntilFound(tester, find.byType(SplashView));
    expect(find.text('get started'), findsOneWidget);
    expect(find.text('login'), findsOneWidget);

    await tester.tap(find.widgetWithText(CupertinoButton, 'login'));
    await pumpUntilFound(tester, find.byType(LoginView));
  });
}
