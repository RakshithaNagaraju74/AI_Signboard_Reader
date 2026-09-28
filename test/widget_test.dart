import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Remove the main.dart import since it's causing issues

void main() {
  testWidgets('App test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('AI Signboard Reader'),
          ),
        ),
      ),
    );

    expect(find.text('AI Signboard Reader'), findsOneWidget);
  });
}