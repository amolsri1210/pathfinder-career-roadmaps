import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pathfinder_app/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> _openApp(WidgetTester tester) async {
  await Hive.initFlutter();
  await Hive.openBox('pathfinder');
  final box = Hive.box('pathfinder');
  box.delete('localUser');
  box.delete('localUsers');
  await tester.pumpWidget(const ProviderScope(child: PathfinderApp()));
  await tester.pump(const Duration(seconds: 1));
}

void _enter(WidgetTester tester, int index, String text) =>
    tester.enterText(find.byType(TextField).at(index), text);

void main() {
  testWidgets('local mode sign up creates an account', (tester) async {
    await _openApp(tester);
    expect(find.text('Sign in'), findsOneWidget);
    await tester.tap(find.text('Sign in').first);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AuthDialog), findsOneWidget);
    await tester.tap(find.text('Create account').first);
    await tester.pump(const Duration(seconds: 1));
    _enter(tester, 0, 'Alice');
    _enter(tester, 1, 'alice@example.com');
    _enter(tester, 2, 'password123');
    await tester.tap(find.text('Create account'));
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text('Account created! Welcome to Pathfinder, Alice.'),
      findsOneWidget,
    );
  });

  testWidgets('local mode sign in welcomes back an existing account',
      (tester) async {
    await _openApp(tester);
    await tester.tap(find.text('Sign in').first);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Create account').first);
    await tester.pump(const Duration(seconds: 1));
    _enter(tester, 0, 'Bob');
    _enter(tester, 1, 'bob@example.com');
    _enter(tester, 2, 'password123');
    await tester.tap(find.text('Create account'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Account created! Welcome to Pathfinder, Bob.'),
        findsOneWidget);

    // Sign in again with the same credentials (dialog: register=false -> email, password)
    await tester.tap(find.text('Sign in').first);
    await tester.pump(const Duration(seconds: 1));
    _enter(tester, 0, 'bob@example.com');
    _enter(tester, 1, 'password123');
    await tester.tap(find.text('Sign in'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text("Welcome back, Bob!"), findsOneWidget);
  });
}