import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pulse_watch_party/src/app.dart';

void main() {
  testWidgets('Pulse app starts', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const PulseApp());

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
