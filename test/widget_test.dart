import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_calc/main.dart';

void main() {
  test('history arithmetic with feet and inch fractions evaluates correctly', () {
    const firstExpression = "1' 2\" 3/4 + 1' 3/4";
    const secondExpression = "2' 6\" 1/2 + 1' 3/4";

    final firstResult = MeasurementParser.evaluate(firstExpression);
    final secondResult = MeasurementParser.evaluate(secondExpression);

    expect(firstResult, isNotNull);
    expect(MeasurementFormatter.formatFeetInches(firstResult!), "2' 3\" 1/2");
    expect(MeasurementFormatter.formatInches(firstResult), "27\" 1/2");

    expect(secondResult, isNotNull);
    expect(MeasurementFormatter.formatFeetInches(secondResult!), "3' 7\" 1/4");
    expect(MeasurementFormatter.formatInches(secondResult), "43\" 1/4");
  });

  test('a previously selected history value can be continued with fractional inch arithmetic without stale formatting', () {
    final previous = MeasurementParser.evaluate("18' 11\" 1/2");
    expect(previous, isNotNull);

    final roundTrip = MeasurementFormatter.formatExpression(previous!);
    final reparsed = MeasurementParser.evaluate(roundTrip);

    expect(reparsed, isNotNull);
    expect(reparsed, previous);

    final next = MeasurementParser.evaluate('$roundTrip - 1" 1/2');
    expect(next, isNotNull);
    expect(MeasurementFormatter.formatFeetInches(next!), "18' 10\"");
    expect(MeasurementFormatter.formatInches(next), "226\"");
  });

  test('decimal values are treated as scalars for multiplication and division', () {
    final half = MeasurementParser.evaluate("2' 6\" x .5");
    final doubled = MeasurementParser.evaluate("2' 6\" ÷ .5");

    expect(half, isNotNull);
    expect(MeasurementFormatter.formatFeetInches(half!), "1' 3\"");
    expect(MeasurementFormatter.formatInches(half), "15\"");

    expect(doubled, isNotNull);
    expect(MeasurementFormatter.formatFeetInches(doubled!), "5' 0\"");
    expect(MeasurementFormatter.formatInches(doubled), "60\"");
  });

  test('scalar addition and subtraction are rejected with an error', () {
    expect(MeasurementParser.evaluate(".5 + 1"), isNull);
    expect(MeasurementParser.evaluate("1 - .5"), isNull);
    expect(MeasurementParser.errorForExpression(".5 + 1"), 'Scalars can only be multiplied or divided');
  });

  test('fractional values are rounded to the nearest 16th of an inch', () {
    final value = MeasurementParser.evaluate("1' 2\" + 5/17");

    expect(value, isNotNull);
    expect(MeasurementFormatter.formatFeetInches(value!), "1' 2\" 5/16");
    expect(MeasurementFormatter.formatInches(value), "14\" 5/16");
  });

  test('operator tokens are parsed as a single unit when backspacing and replacing', () {
    final expression = "1' 2\" + ";
    final stripped = RegExp(r'^(.*?)(?:\s*[+\-x÷]\s*)$').firstMatch(expression)?.group(1) ?? expression;

    expect(stripped, "1' 2\"");
    expect(stripped + ' + ', "1' 2\" + ");
  });

  testWidgets('history row selection keeps the formula in the output display and leaves the input field empty', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final history = [
      HistoryEntry(
        text: "1' 2\" 3/4 + 1' 3/4 = 2' 3\" 1/2",
        createdAt: DateTime.now(),
      ),
    ];

    String? selectedInput;
    String? selectedResult;

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryScreen(
          history: history,
          onInputSelected: (value) => selectedInput = value,
          onResultSelected: (value) => selectedResult = value,
          onClear: () {},
        ),
      ),
    );

    expect(find.text('Today'), findsOneWidget);
    expect(find.text("1' 2\" 3/4 + 1' 3/4"), findsOneWidget);
    expect(find.text("2' 3\" 1/2"), findsOneWidget);

    await tester.tap(find.text("2' 3\" 1/2"));
    await tester.pump();

    expect(selectedResult, "1' 2\" 3/4 + 1' 3/4 = 2' 3\" 1/2");
    expect(selectedInput, isNull);

    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text("1"));
    await tester.tap(find.text("'"));
    await tester.tap(find.text("2"));
    await tester.tap(find.text('"'));
    await tester.tap(find.text('3'));
    await tester.tap(find.text('/'));
    await tester.tap(find.text('4'));
    await tester.tap(find.text('+'));
    await tester.tap(find.text("1"));
    await tester.tap(find.text("'"));
    await tester.tap(find.text('3'));
    await tester.tap(find.text('/'));
    await tester.tap(find.text('4'));
    await tester.tap(find.text('='));
    await tester.pump();

    expect(find.text("2' 3\" 1/2"), findsWidgets);
    final fieldText = tester.widget<TextField>(find.byType(TextField)).controller!.text;
    expect(fieldText, isEmpty);
  });

  testWidgets('equals evaluates a basic measurement correctly', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('1'));
    await tester.tap(find.text("'"));
    await tester.tap(find.text('2'));
    await tester.tap(find.text('"'));
    await tester.tap(find.text('='));
    await tester.pump();

    expect(find.text("1' 2\""), findsNWidgets(2));
    expect(find.text('14"'), findsOneWidget);
  });

  testWidgets('backspace removes the whole operator token and leaves no extra leading space', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('1'));
    await tester.tap(find.text("'"));
    await tester.tap(find.text('2'));
    await tester.tap(find.text('"'));
    await tester.tap(find.text('+'));
    await tester.tap(find.text('⌫'));
    await tester.pump();

    final fieldAfterBackspace = tester.widget<TextField>(find.byType(TextField));
    expect(fieldAfterBackspace.controller!.text, "1' 2\"");

    await tester.tap(find.text('+'));
    await tester.pump();

    final fieldAfterOperator = tester.widget<TextField>(find.byType(TextField));
    expect(fieldAfterOperator.controller!.text, "1' 2\" + ");
  });

  testWidgets('shows memory controls and opens the memory screen', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MyApp());

    expect(find.text('MS'), findsOneWidget);
    expect(find.text('MR'), findsOneWidget);
    expect(find.text('MEM'), findsOneWidget);

    await tester.tap(find.text('MEM'));
    await tester.pumpAndSettle();

    expect(find.text('Memory'), findsOneWidget);
    expect(find.text('No saved values'), findsOneWidget);
  });
}
