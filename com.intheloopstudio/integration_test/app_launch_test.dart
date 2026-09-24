import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intheloopapp/main.dart' as app;
import 'package:intheloopapp/ui/forms/email_text_field.dart';
import 'package:intheloopapp/ui/forms/password_text_field.dart';
import 'package:intheloopapp/ui/login/login_view.dart';
import 'package:intheloopapp/ui/onboarding/onboarding_view.dart';
import 'package:intheloopapp/ui/shell/shell_view.dart';
import 'package:intheloopapp/ui/splash/splash_view.dart';

const _testEmail = String.fromEnvironment(
  'TEST_EMAIL',
  defaultValue: 'testaccount@email.com',
);
const _testPassword = String.fromEnvironment(
  'TEST_PASSWORD',
  defaultValue: 'Welcome123!',
);

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

  testWidgets('app finishes initialising and can log in', (tester) async {
    await app.main();

    await pumpUntilFound(tester, find.byType(SplashView));
    expect(find.text('get started'), findsOneWidget);
    expect(find.text('login'), findsOneWidget);

    await tester.tap(find.widgetWithText(CupertinoButton, 'login'));
    await pumpUntilFound(tester, find.byType(LoginView));

    await tester.enterText(find.byType(EmailTextField), _testEmail);
    await tester.enterText(find.byType(PasswordTextField), _testPassword);
    await tester.pump();
    await tester.tap(find.widgetWithText(CupertinoButton, 'login'));

    final signedIn = find.byWidgetPredicate(
      (w) => w is ShellView || w is OnboardingView,
    );
    await pumpUntilFound(
      tester,
      signedIn,
      timeout: const Duration(seconds: 120),
    );
    expect(find.byType(LoginView), findsNothing);
    expect(FirebaseAuth.instance.currentUser?.email, _testEmail);
  });
}
