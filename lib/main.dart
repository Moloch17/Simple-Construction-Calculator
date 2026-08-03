import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple Construction Calculator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        scaffoldBackgroundColor: const Color(0xFF121212),
        textTheme: ThemeData.dark().textTheme,
      ),
      home: const MeasurementCalculator(),
    );
  }
}

class MeasurementCalculator extends StatefulWidget {
  const MeasurementCalculator({super.key});

  @override
  State<MeasurementCalculator> createState() => _MeasurementCalculatorState();
}

class _MeasurementCalculatorState extends State<MeasurementCalculator> {
  final TextEditingController _expressionController = TextEditingController();
  final FocusNode _expressionFocus = FocusNode();
  final ScrollController _inputScrollController = ScrollController();
  final GlobalKey _inputKey = GlobalKey();
  String _lastExpression = '';
  String _resultFeetInches = '0\' 0"';
  String _resultInches = '0"';
  String _errorMessage = '';
  final List<HistoryEntry> _history = [];
  final List<MemoryItem> _memory = [];
  Fraction? _lastResult;
  static const String _historyKey = 'calculator_history';
  static const String _memoryKey = 'calculator_memory';

  final List<List<String>> _buttonRows = const [
    ['1', '2', '3', '÷'],
    ['4', '5', '6', 'x'],
    ['7', '8', '9', '-'],
    ['0', '\'', '"', '+'],
    ['/', '.', '⌫', '='],
    ['MS', 'MR', 'MEM', 'C'],
  ];

  @override
  void initState() {
    super.initState();
    _setExpressionValue('', 0);
    _loadHistory();
    _loadMemory();
    _expressionFocus.requestFocus();
  }

  void _setExpressionValue(String text, int cursor) {
    _expressionController.text = text;
    final pos = cursor.clamp(0, text.length);
    _expressionController.selection = TextSelection.collapsed(offset: pos);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelection());
  }

  void _scrollToSelection() {
    try {
      final selection = _expressionController.selection;
      final end = selection.isValid ? selection.start : _expressionController.text.length;
      final textBefore = _expressionController.text.substring(0, end.clamp(0, _expressionController.text.length));
      final tp = TextPainter(
        text: TextSpan(text: textBefore, style: const TextStyle(fontSize: 22, color: Colors.white70)),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      final caretX = tp.width;
      final boxWidth = _inputKey.currentContext?.size?.width ?? 200.0;
      final maxScroll = _inputScrollController.hasClients ? _inputScrollController.position.maxScrollExtent : 0.0;
      var target = caretX - boxWidth + 24.0;
      if (target < 0) target = 0.0;
      if (target > maxScroll) target = maxScroll;
      if (_inputScrollController.hasClients) {
        _inputScrollController.animateTo(target, duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
      }
    } catch (_) {}
  }

  void _onButtonPressed(String value) {
    if (value == 'MS') {
      _saveToMemory();
      return;
    }

    if (value == 'MR') {
      _recallMemory();
      return;
    }

    if (value == 'MEM') {
      _showMemory();
      return;
    }

    setState(() {
      if (value == 'C') {
        _setExpressionValue('', 0);
        _errorMessage = '';
        _lastExpression = '';
        _resultFeetInches = '0\' 0"';
        _resultInches = '0"';
        _lastResult = null;
        return;
      }

      if (value == '⌫') {
        _backspace();
        return;
      }

      if (value == '=') {
        _evaluateExpression();
        return;
      }

      final text = _expressionController.text;
      final selection = _expressionController.selection;
      final isOperator = _isOperator(value);
      final insertText = value == '/'
          ? '/'
          : (value == '\'' || value == '"')
              ? '$value '
              : (value == '.' ? '.' : (isOperator ? ' $value ' : value));

      if (text.isEmpty && isOperator && _lastResult != null) {
        final lastExpression = MeasurementFormatter.formatExpression(_lastResult!);
        _setExpressionValue('$lastExpression $value ', ('$lastExpression $value ').length);
        return;
      }

      if (text.isEmpty && isOperator && value != '-') {
        return;
      }

      if (selection.isValid) {
        final start = selection.start;
        final end = selection.end;
        final before = text.substring(0, start);
        final after = text.substring(end);

        if (isOperator && text.isNotEmpty && start > 0) {
          final previous = _previousNonSpaceChar(text, start);
          if (_isOperator(previous)) {
            final replaceStart = text.lastIndexOf(previous, start - 1);
            final beforeOperator = text.substring(0, replaceStart).trimRight();
            final afterOperator = after.trimLeft();
            final combined = afterOperator.isEmpty
                ? '$beforeOperator $value '
                : '$beforeOperator $value $afterOperator';
            _setExpressionValue(combined, '$beforeOperator $value '.length);
            return;
          }
        }
        final newExpression = before + insertText + after;
        final cursorPosition = (before + insertText).length;
        _setExpressionValue(newExpression, cursorPosition);
      } else {
        final normalizedText = isOperator && text.isNotEmpty ? _stripTrailingOperatorToken(text) : text;
        final appended = normalizedText + insertText;
        _setExpressionValue(appended, appended.length);
      }
    });
  }

  String _previousNonSpaceChar(String text, int index) {
    for (var i = index - 1; i >= 0; i--) {
      if (text[i] != ' ') return text[i];
    }
    return '';
  }

  bool _isOperator(String value) {
    return value == '+' || value == '-' || value == 'x' || value == '÷';
  }

  String _stripTrailingOperatorToken(String text) {
    if (text.isEmpty) return text;
    final trimmed = text.trimRight();
    final match = RegExp(r'^(.*?)(?:\s*[+\-x÷]\s*)$').firstMatch(trimmed);
    if (match == null) return text;
    final prefix = match.group(1) ?? '';
    return prefix;
  }

  void _backspace() {
    final text = _expressionController.text;
    final selection = _expressionController.selection;
    if (!selection.isValid) return;

    if (selection.start != selection.end) {
      final before = text.substring(0, selection.start);
      final after = text.substring(selection.end);
      _setExpressionValue(before + after, before.length);
      return;
    }

    final cursorPosition = selection.start;
    if (cursorPosition == 0) return;

    final before = text.substring(0, cursorPosition);
    final trimmedBefore = before.trimRight();
    final match = RegExp(r'^(.*?)(?:\s*[+\-x÷]\s*)$').firstMatch(trimmedBefore);
    if (match != null) {
      final prefix = match.group(1) ?? '';
      _setExpressionValue(prefix, prefix.length);
      return;
    }

    final updatedBefore = text.substring(0, cursorPosition - 1);
    final updatedAfter = text.substring(cursorPosition);
    _setExpressionValue(updatedBefore + updatedAfter, updatedBefore.length);
  }

  void _saveToMemory() {
    if (_lastResult == null && _resultFeetInches == '0\' 0"' && _resultInches == '0"') {
      return;
    }

    final valueToStore = _resultFeetInches.isNotEmpty ? _resultFeetInches : _resultInches;
    if (_memory.isNotEmpty && _memory.first.value == valueToStore) {
      return;
    }

    final newItem = MemoryItem(value: valueToStore, note: '');

    setState(() {
      _memory.insert(0, newItem);
      if (_memory.length > 20) {
        _memory.removeLast();
      }
    });
    _saveMemory();
  }

  void _recallMemory() {
    if (_memory.isEmpty) return;
    setState(() {
      _insertMemoryValue(_memory.first.value);
    });
  }

  void _insertMemoryValue(String value) {
    final text = _expressionController.text;
    final selection = _expressionController.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final before = text.substring(0, start);
    final after = text.substring(end);
    final newExpression = '$before$value$after';
    _setExpressionValue(newExpression, start + value.length);
    _lastExpression = newExpression;
  }

  void _applyMemoryItem(MemoryItem item) {
    setState(() {
      _insertMemoryValue(item.value);
      final parsedResult = MeasurementParser.evaluate(item.value);
      if (parsedResult != null) {
        _resultFeetInches = MeasurementFormatter.formatFeetInches(parsedResult);
        _resultInches = MeasurementFormatter.formatInches(parsedResult);
        _lastResult = parsedResult;
        _errorMessage = '';
      } else {
        _resultFeetInches = item.value;
        _resultInches = item.value;
      }
    });
  }

  void _evaluateExpression() {
    var expression = _expressionController.text.trim();
    if (expression.isEmpty && _lastExpression.isNotEmpty) {
      expression = _lastExpression.trim();
      _setExpressionValue(expression, expression.length);
    }
    if (expression.isEmpty) return;
    _lastExpression = expression;

    final parserError = MeasurementParser.errorForExpression(expression);
    if (parserError != null) {
      _errorMessage = parserError;
      _lastResult = null;
      _resultFeetInches = parserError;
      _resultInches = parserError;
      return;
    }

    final result = MeasurementParser.evaluate(expression);
    if (result == null) {
      _errorMessage = 'Invalid expression';
      _resultFeetInches = 'Invalid expression';
      _resultInches = 'Invalid expression';
      return;
    }
    _errorMessage = '';
    _resultFeetInches = MeasurementFormatter.formatFeetInches(result);
    _resultInches = MeasurementFormatter.formatInches(result);
    _lastResult = result;
    _history.add(HistoryEntry(
      text: '$expression = ${MeasurementFormatter.formatFeetInches(result)}',
      createdAt: DateTime.now(),
    ));
    _saveHistory();
    _setExpressionValue('', 0);
  }

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
        contentTextStyle: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
        title: const Text('Help'),
        content: const SingleChildScrollView(
          child: Text(
            'How to enter measurements:\n\n'
            '• Enter a number, then the feet sign (\').\n'
            '• Enter an operator.\n'
            '• Enter a number, then the inches sign (").\n'
            '• Enter the fraction.\n\n'
            'Example: 1\' 2" 3/4\n\n'
            'If units are left out, they are assumed to be inches.\n\n'
            'Other notes:\n'
            '• Tapping the output box opens the calculation history.\n'
            '• Memory items can be deleted by swiping right.'
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Construction Calculator'),
        centerTitle: true,
        backgroundColor: const Color(0xFF4A90E2),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Help',
            onPressed: _showHelp,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildResultDisplay(),
              const SizedBox(height: 16),
              _buildExpressionDisplay(),
              const SizedBox(height: 24),
              ..._buttonRows.map((row) => _buildButtonRow(row)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultDisplay() {
    final hasError = _errorMessage.isNotEmpty;

    return GestureDetector(
      onTap: _showHistory,
      child: Container(
        height: 116,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 26,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _lastExpression,
                  textAlign: TextAlign.start,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (hasError)
              const SizedBox(height: 8),
            if (hasError)
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _errorMessage,
                    textAlign: TextAlign.left,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              )
            else ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _resultFeetInches,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        _resultInches,
                        style: const TextStyle(fontSize: 20, color: Colors.white70),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openScreen(Widget screen) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => Theme(
          data: Theme.of(context).copyWith(scaffoldBackgroundColor: const Color(0xFF121212)),
          child: screen,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        opaque: true,
      ),
    );
  }

  void _showMemory() {
    _openScreen(
      MemoryScreen(
        memory: _memory,
        onValueSelected: (item) {
          setState(() {
            _insertMemoryValue(item.value);
          });
          Navigator.of(context).pop();
        },
        onMemoryChanged: (updatedMemory) {
          setState(() {
            _memory
              ..clear()
              ..addAll(updatedMemory);
          });
          _saveMemory();
        },
      ),
    );
  }

  void _applyHistorySelection(String selectedExpression, {String? selectedResult}) {
    final expression = selectedExpression.trim();
    final resultText = (selectedResult ?? '').trim();
    final displayExpression = expression.isNotEmpty ? expression : resultText;
    final parsedResult = displayExpression.isEmpty ? null : MeasurementParser.evaluate(displayExpression);

    setState(() {
      _setExpressionValue('', 0);
      _lastExpression = displayExpression;
      _errorMessage = '';

      if (parsedResult != null) {
        _resultFeetInches = resultText.isNotEmpty ? resultText : MeasurementFormatter.formatFeetInches(parsedResult);
        _resultInches = resultText.isNotEmpty ? resultText : MeasurementFormatter.formatInches(parsedResult);
        _lastResult = parsedResult;
      } else {
        _resultFeetInches = resultText;
        _resultInches = resultText;
        _lastResult = null;
      }
    });
  }

  void _showHistory() {
    _openScreen(
      HistoryScreen(
        history: _history,
        onInputSelected: (entry) {
          final separator = ' = ';
          final selectedExpression = entry.contains(separator) ? entry.split(separator).first : entry;
          _applyHistorySelection(selectedExpression);
        },
        onResultSelected: (entry) {
          final separator = ' = ';
          final selectedExpression = entry.contains(separator) ? entry.split(separator).first : '';
          final selectedResult = entry.contains(separator) ? entry.split(separator).last : entry;
          _applyHistorySelection(selectedExpression, selectedResult: selectedResult);
        },
        onClear: () {
          setState(() {
            _history.clear();
            _saveHistory();
          });
        },
      ),
    );
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final savedHistory = prefs.getStringList(_historyKey);
    if (savedHistory == null) return;
    setState(() {
      _history
        ..clear()
        ..addAll(savedHistory.map(HistoryEntry.fromStorageString));
    });
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, _history.map((entry) => entry.toStorageString()).toList());
  }

  Future<void> _loadMemory() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMemory = prefs.getStringList(_memoryKey);
    if (savedMemory == null) return;
    setState(() {
      _memory
        ..clear()
        ..addAll(savedMemory.take(20).map(MemoryItem.fromStorageString));
    });
  }

  Future<void> _saveMemory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_memoryKey, _memory.map((item) => item.toStorageString()).toList());
  }

  Widget _buildExpressionDisplay() {
    return Container(
      key: _inputKey,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF212121),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: _expressionController,
        scrollController: _inputScrollController,
        focusNode: _expressionFocus,
        readOnly: true,
        showCursor: true,
        enableInteractiveSelection: true,
        autofocus: true,
        style: const TextStyle(fontSize: 22, color: Colors.white70),
        decoration: const InputDecoration(
          hintText: 'Enter calculation',
          hintStyle: TextStyle(color: Colors.white38),
          border: InputBorder.none,
        ),
        cursorColor: Colors.white,
      ),
    );
  }

  Widget _buildButtonRow(List<String> row) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: row
            .map(
              (label) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _buildCalcButton(label),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildCalcButton(String label) {
    final bool isOperator = _isOperator(label) || label == '=' || label == 'C';
    final bool isMemoryAction = label == 'MS' || label == 'MR' || label == 'MEM';
    return ElevatedButton(
      onPressed: label.isEmpty ? null : () => _onButtonPressed(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: isOperator
            ? Colors.orange.shade700
            : isMemoryAction
                ? Colors.teal.shade700
                : Colors.grey.shade800,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(70),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class MemoryItem {
  MemoryItem({required this.value, required this.note});

  final String value;
  String note;

  String toStorageString() => '$value::${Uri.encodeComponent(note)}';

  factory MemoryItem.fromStorageString(String entry) {
    final parts = entry.split('::');
    if (parts.isEmpty) {
      return MemoryItem(value: '', note: '');
    }
    return MemoryItem(
      value: parts.first,
      note: parts.length > 1 ? Uri.decodeComponent(parts[1]) : '',
    );
  }
}

class MemoryScreen extends StatefulWidget {
  final List<MemoryItem> memory;
  final ValueChanged<MemoryItem> onValueSelected;
  final ValueChanged<List<MemoryItem>> onMemoryChanged;

  const MemoryScreen({
    super.key,
    required this.memory,
    required this.onValueSelected,
    required this.onMemoryChanged,
  });

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  late List<MemoryItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List<MemoryItem>.from(widget.memory);
  }

  Future<void> _editNote(int index) async {
    final controller = TextEditingController(text: _items[index].note);
    final updatedNote = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        contentTextStyle: const TextStyle(color: Colors.white70),
        title: const Text('Edit note'),
        content: SizedBox(
          width: 280,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 1,
            maxLines: 1,
            style: const TextStyle(color: Colors.white),
            cursorColor: Colors.white,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Add a note',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF212121),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white24, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white24, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.lightBlueAccent, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Save')),
        ],
      ),
    );

    if (updatedNote != null) {
      setState(() {
        _items[index].note = updatedNote;
      });
      widget.onMemoryChanged(_items);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory'),
        backgroundColor: const Color(0xFF4A90E2),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear memory',
            onPressed: () {
              setState(() {
                _items.clear();
              });
              widget.onMemoryChanged(_items);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: _items.isEmpty
          ? const Center(
              child: Text(
                'No saved values',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length > 20 ? 20 : _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return Dismissible(
                  key: ValueKey(item.value + item.note + index.toString()),
                  direction: DismissDirection.startToEnd,
                  background: Container(
                    decoration: BoxDecoration(
                      color: Colors.red.shade700,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: const Icon(Icons.delete_outline, color: Colors.white, size: 24),
                  ),
                  onDismissed: (_) {
                    setState(() {
                      _items.removeAt(index);
                    });
                    widget.onMemoryChanged(_items);
                  },
                  child: Container(
                    color: index.isEven ? Colors.grey.shade900 : Colors.grey.shade800,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => widget.onValueSelected(item),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                item.value,
                                style: const TextStyle(color: Colors.white, fontSize: 18),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 140,
                          child: InkWell(
                            onTap: () => _editNote(index),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                item.note.isEmpty ? 'Tap to note' : item.note,
                                textAlign: TextAlign.end,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70, fontSize: 16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class HistoryEntry {
  final String text;
  final DateTime createdAt;

  const HistoryEntry({required this.text, required this.createdAt});

  String toStorageString() => '${createdAt.millisecondsSinceEpoch}::${Uri.encodeComponent(text)}';

  static HistoryEntry fromStorageString(String entry) {
    final parts = entry.split('::');
    if (parts.length >= 2 && int.tryParse(parts.first) != null) {
      final timestamp = int.parse(parts.first);
      final text = parts.sublist(1).join('::');
      return HistoryEntry(
        text: Uri.decodeComponent(text),
        createdAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
      );
    }

    return HistoryEntry(text: entry, createdAt: DateTime.now());
  }
}

class HistoryScreen extends StatelessWidget {
  final List<HistoryEntry> history;
  final ValueChanged<String> onInputSelected;
  final ValueChanged<String> onResultSelected;
  final VoidCallback onClear;

  const HistoryScreen({
    super.key,
    required this.history,
    required this.onInputSelected,
    required this.onResultSelected,
    required this.onClear,
  });

  String _formatDayLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${_monthName(date.month)} ${date.day}, ${date.year}';
  }

  String _monthName(int month) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return names[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    final orderedEntries = List<HistoryEntry>.from(history.reversed);
    final groupedEntries = <DateTime, List<HistoryEntry>>{};

    for (final entry in orderedEntries) {
      final day = DateTime(entry.createdAt.year, entry.createdAt.month, entry.createdAt.day);
      groupedEntries.putIfAbsent(day, () => <HistoryEntry>[]).add(entry);
    }

    final rows = <Widget>[];
    for (final entry in groupedEntries.entries) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Text(
            _formatDayLabel(entry.key),
            style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      );
      for (final historyEntry in entry.value) {
        final separator = ' = ';
        final entryText = historyEntry.text;
        final inputText = entryText.contains(separator) ? entryText.split(separator).first : entryText;
        final resultText = entryText.contains(separator) ? entryText.split(separator).last : '';
        rows.add(
          Container(
            color: rows.length.isEven ? Colors.grey.shade900 : Colors.grey.shade800,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: InkWell(
                    onTap: () {
                      onInputSelected(entryText);
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        inputText,
                        style: const TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: InkWell(
                    onTap: () {
                      onResultSelected(entryText);
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        resultText,
                        textAlign: TextAlign.end,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      rows.add(const SizedBox(height: 12));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calculation History'),
        backgroundColor: const Color(0xFF4A90E2),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear history',
            onPressed: () {
              onClear();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: history.isEmpty
          ? const Center(
              child: Text(
                'No history yet',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: rows,
            ),
    );
  }
}

class MeasurementFormatter {
  static Fraction _roundToNearestSixteenth(Fraction value) {
    final absValue = value.abs();
    final sixteenths = absValue * Fraction.fromInt(16);
    final wholeSixteenths = sixteenths.toWholeNumber();
    final remainder = sixteenths - Fraction.fromInt(wholeSixteenths.toInt());
    final roundedSixteenths = remainder >= Fraction.oneHalf() ? wholeSixteenths.toInt() + 1 : wholeSixteenths.toInt();
    final roundedValue = Fraction.fromInt(roundedSixteenths) / Fraction.fromInt(16);
    return value.isNegative ? -roundedValue : roundedValue;
  }

  static String formatFeetInches(Fraction value) {
    final roundedValue = _roundToNearestSixteenth(value);
    final sign = roundedValue.isNegative ? '-' : '';
    final absValue = roundedValue.abs();
    final totalInches = absValue.toWholeNumber().toInt();
    final feet = totalInches ~/ 12;
    final inches = totalInches % 12;
    final remainder = absValue - Fraction.fromInt(totalInches);
    final fractionPart = _fractionToNearestSixteenth(remainder);

    if (fractionPart.isZero) {
      return '$sign${feet.toString()}\' ${inches.toString()}"';
    }

    final fractionText = '${fractionPart.numerator}/${fractionPart.denominator}';
    if (inches == 0) {
      return '$sign${feet.toString()}\' 0" $fractionText';
    }
    return '$sign${feet.toString()}\' ${inches.toString()}" $fractionText';
  }

  static String formatInches(Fraction value) {
    final roundedValue = _roundToNearestSixteenth(value);
    final sign = roundedValue.isNegative ? '-' : '';
    final absValue = roundedValue.abs();
    final totalInches = absValue.toWholeNumber().toInt();
    final remainder = absValue - Fraction.fromInt(totalInches);
    final fractionPart = _fractionToNearestSixteenth(remainder);
    if (fractionPart.isZero) {
      return '$sign$totalInches"';
    }
    return '$sign$totalInches" ${fractionPart.numerator}/${fractionPart.denominator}';
  }

  static Fraction _fractionToNearestSixteenth(Fraction value) {
    final scaled = value * Fraction.fromInt(16);
    final roundedSixteenths = scaled.toWholeNumber();
    return Fraction(roundedSixteenths, BigInt.from(16));
  }

  static String formatExpression(Fraction value) {
    return formatFeetInches(value);
  }
}

class MeasurementParser {
  static String? errorForExpression(String expression) {
    final tokens = _tokenize(expression);
    if (tokens.isEmpty) return null;

    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token != '+' && token != '-') continue;
      if (i == 0 || i == tokens.length - 1) continue;
      final left = tokens[i - 1];
      final right = tokens[i + 1];
      if (_isScalarToken(left) && _isScalarToken(right)) {
        return 'Scalars can only be multiplied or divided';
      }
    }

    return null;
  }

  static bool _isScalarToken(String token) {
    final normalized = token.trim();
    if (normalized.isEmpty) return false;
    if (normalized.contains("'") || normalized.contains('"')) return false;
    return normalized.contains('.') || int.tryParse(normalized) != null || (normalized.contains('/') && normalized.split('/').length == 2);
  }

  static Fraction? evaluate(String expression) {
    final error = errorForExpression(expression);
    if (error != null) return null;
    final tokens = _tokenize(expression);
    if (tokens.isEmpty) return null;
    final rpn = _toRpn(tokens);
    if (rpn == null) return null;
    return _evaluateRpn(rpn);
  }

  static List<String> _tokenize(String expression) {
    final cleaned = expression.replaceAll(' ', '');
    final tokens = <String>[];
    final buffer = StringBuffer();

    for (var i = 0; i < cleaned.length; i++) {
      final char = cleaned[i];
      if (char == '+' || char == '-' || char == 'x' || char == '÷') {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        if (char == '-' && (tokens.isEmpty || _isOperator(tokens.last))) {
          buffer.write(char);
        } else {
          tokens.add(char);
        }
      } else {
        buffer.write(char);
      }
    }

    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
    }
    return tokens;
  }

  static bool _isOperator(String token) {
    return token == '+' || token == '-' || token == 'x' || token == '÷' || token == '/';
  }

  static int _precedence(String op) {
    if (op == 'x' || op == '÷') return 2;
    return 1;
  }

  static List<String>? _toRpn(List<String> tokens) {
    final output = <String>[];
    final operators = <String>[];

    for (final token in tokens) {
      if (_isOperator(token)) {
        while (operators.isNotEmpty && _isOperator(operators.last) && _precedence(operators.last) >= _precedence(token)) {
          output.add(operators.removeLast());
        }
        operators.add(token);
      } else {
        output.add(token);
      }
    }

    while (operators.isNotEmpty) {
      output.add(operators.removeLast());
    }

    return output;
  }

  static Fraction? _evaluateRpn(List<String> rpn) {
    final stack = <Fraction>[];

    for (final token in rpn) {
      if (_isOperator(token)) {
        if (stack.length < 2) return null;
        final right = stack.removeLast();
        final left = stack.removeLast();
        final result = _applyOperator(left, right, token);
        if (result == null) return null;
        stack.add(result);
      } else {
        final value = _parseMeasurement(token);
        if (value == null) return null;
        stack.add(value);
      }
    }

    return stack.length == 1 ? stack.first : null;
  }

  static Fraction? _applyOperator(Fraction left, Fraction right, String op) {
    switch (op) {
      case '+':
        return left + right;
      case '-':
        return left - right;
      case 'x':
        return left * right;
      case '÷':
        if (right.isZero) return null;
        return left / right;
      default:
        return null;
    }
  }

  static Fraction? _parseMeasurement(String input) {
    if (input.isEmpty) return null;
    var token = input.replaceAll(' ', '');
    var sign = 1;
    if (token.startsWith('-')) {
      sign = -1;
      token = token.substring(1);
    }

    if (token == '.' || token == '') return null;

    if (token.contains('.') && !token.contains("'") && !token.contains('"')) {
      final parsedDecimal = _parseDecimalPart(token);
      if (parsedDecimal == null) return null;
      return sign == -1 ? -parsedDecimal : parsedDecimal;
    }

    int feet = 0;
    Fraction inches = Fraction.zero;
    Fraction fraction = Fraction.zero;

    final firstFeetIndex = token.indexOf("'");
    if (firstFeetIndex >= 0) {
      final feetPart = token.substring(0, firstFeetIndex);
      feet = int.tryParse(feetPart) ?? 0;
      token = token.substring(firstFeetIndex + 1);
    }

    if (token.isEmpty) {
      final totalInches = Fraction.fromInt(feet * 12) + inches + fraction;
      return sign == -1 ? -totalInches : totalInches;
    }

    final hasInchQuote = token.contains('"');
    final hasExtraFeetQuote = !hasInchQuote && token.contains("'");
    if (hasExtraFeetQuote) {
      token = token.replaceFirst("'", '"');
    }

    if (token.contains('"')) {
      final parts = token.split('"');
      final inchesPart = parts[0];
      final fractionPart = parts.length > 1 ? parts.sublist(1).join('"') : '';
      if (inchesPart.isNotEmpty) {
        final parsedInches = _parseInchPart(inchesPart);
        if (parsedInches == null) return null;
        inches = parsedInches;
      }
      if (fractionPart.isNotEmpty) {
        final parsedFraction = _parseFractionPart(fractionPart);
        if (parsedFraction == null) return null;
        fraction = parsedFraction;
      }
    } else if (token.contains('/')) {
      final parsedFraction = _parseFractionPart(token);
      if (parsedFraction == null) return null;
      fraction = parsedFraction;
    } else if (token.isNotEmpty) {
      final parsedInches = _parseInchPart(token);
      if (parsedInches == null) return null;
      inches = parsedInches;
    }

    final totalInches = Fraction.fromInt(feet * 12) + inches + fraction;
    return sign == -1 ? -totalInches : totalInches;
  }

  static Fraction? _parseDecimalPart(String part) {
    final cleaned = part.trim();
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '-.' || cleaned == '+.') return null;
    if (!cleaned.contains('.')) return null;

    final split = cleaned.split('.');
    if (split.length != 2) return null;
    final wholePart = split[0].isEmpty ? '0' : split[0];
    final fractionPart = split[1];
    if (fractionPart.isEmpty) {
      final whole = int.tryParse(wholePart);
      return whole == null ? null : Fraction.fromInt(whole);
    }

    final whole = int.tryParse(wholePart);
    final digits = fractionPart.replaceAll(RegExp(r'[^0-9]'), '');
    if (whole == null || digits.isEmpty) return null;

    final denominator = BigInt.from(10).pow(digits.length);
    final numerator = (BigInt.from(whole) * denominator) + BigInt.parse(digits);
    return Fraction(numerator, denominator);
  }

  static Fraction? _parseFractionPart(String part) {
    if (part.isEmpty) return Fraction.zero;
    final cleaned = part.replaceAll('"', '').replaceAll("'", '');
    if (!cleaned.contains('/')) return null;
    final fractionParts = cleaned.split('/');
    if (fractionParts.length != 2) return null;
    final numerator = int.tryParse(fractionParts[0]);
    final denominator = int.tryParse(fractionParts[1]);
    if (numerator == null || denominator == null || denominator == 0) return null;
    return Fraction(BigInt.from(numerator), BigInt.from(denominator));
  }

  static Fraction? _parseInchPart(String part) {
    if (part.isEmpty) return Fraction.zero;
    if (part.contains('/')) {
      final fractionParts = part.split('/');
      if (fractionParts.length != 2) return null;
      final numerator = int.tryParse(fractionParts[0]);
      final denominator = int.tryParse(fractionParts[1]);
      if (numerator == null || denominator == null || denominator == 0) return null;
      return Fraction(BigInt.from(numerator), BigInt.from(denominator));
    }
    final whole = int.tryParse(part);
    if (whole == null) return null;
    return Fraction.fromInt(whole);
  }
}

class Fraction {
  final BigInt numerator;
  final BigInt denominator;

  const Fraction._internal(this.numerator, this.denominator);

  static final Fraction zero = Fraction._internal(BigInt.zero, BigInt.one);

  factory Fraction(BigInt numerator, BigInt denominator) {
    if (denominator == BigInt.zero) throw ArgumentError('Denominator cannot be zero');
    final sign = denominator.isNegative ? -BigInt.one : BigInt.one;
    final normalizedDenominator = denominator.abs();
    final normalizedNumerator = numerator * sign;
    final gcdValue = normalizedNumerator.gcd(normalizedDenominator);
    return Fraction._internal(normalizedNumerator ~/ gcdValue, normalizedDenominator ~/ gcdValue);
  }

  factory Fraction.fromInt(int value) => Fraction(BigInt.from(value), BigInt.one);

  static Fraction oneHalf() => Fraction(BigInt.one, BigInt.from(2));

  bool get isZero => numerator == BigInt.zero;
  bool get isNegative => numerator.isNegative;

  Fraction abs() => Fraction(numerator.abs(), denominator);

  int compareTo(Fraction other) {
    final lhs = numerator * other.denominator;
    final rhs = other.numerator * denominator;
    if (lhs < rhs) return -1;
    if (lhs > rhs) return 1;
    return 0;
  }

  bool operator >(Fraction other) => compareTo(other) > 0;
  bool operator >=(Fraction other) => compareTo(other) >= 0;
  bool operator <(Fraction other) => compareTo(other) < 0;
  bool operator <=(Fraction other) => compareTo(other) <= 0;

  Fraction operator +(Fraction other) => Fraction(numerator * other.denominator + other.numerator * denominator, denominator * other.denominator);
  Fraction operator -(Fraction other) => Fraction(numerator * other.denominator - other.numerator * denominator, denominator * other.denominator);
  Fraction operator *(Fraction other) => Fraction(numerator * other.numerator, denominator * other.denominator);
  Fraction operator /(Fraction other) => Fraction(numerator * other.denominator, denominator * other.numerator);

  Fraction operator -() => Fraction(-numerator, denominator);

  Fraction simplified() => Fraction(numerator, denominator);

  BigInt toWholeNumber() {
    return numerator ~/ denominator;
  }

  @override
  String toString() {
    if (denominator == BigInt.one) return numerator.toString();
    return '$numerator/$denominator';
  }

  Fraction operator %(Fraction other) {
    final div = toWholeNumber();
    return this - other * Fraction.fromInt(div.toInt());
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Fraction && numerator == other.numerator && denominator == other.denominator;
  }

  @override
  int get hashCode => Object.hash(numerator, denominator);
}
