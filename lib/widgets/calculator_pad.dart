import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../main.dart';

/// In-screen calculator pad for the amount field.
///
/// Digits, `+ − × ÷`, `=`, clear and backspace. The expression is evaluated
/// by a small hand-written parser ([_evaluate]) — no extra dependency.
/// Pressing `=` calls [onResult] with the value so the parent can fill the
/// amount field; the result stays in the display for chained calculations.
class CalculatorPad extends StatefulWidget {
  final ValueChanged<double> onResult;

  const CalculatorPad({super.key, required this.onResult});

  @override
  State<CalculatorPad> createState() => _CalculatorPadState();
}

class _CalculatorPadState extends State<CalculatorPad> {
  String _expr = '';

  static const List<String> _keys = [
    'C', '⌫', '÷', '×',
    '7', '8', '9', '−',
    '4', '5', '6', '+',
    '1', '2', '3', '=',
    '0', '00', '.', '=',
  ];

  bool _isOperator(String s) =>
      s == '+' || s == '−' || s == '×' || s == '÷';

  void _press(String key) {
    setState(() {
      switch (key) {
        case 'C':
          _expr = '';
        case '⌫':
          if (_expr.isNotEmpty) {
            _expr = _expr.substring(0, _expr.length - 1);
          }
        case '=':
          final result = _evaluate(_expr);
          if (result != null) {
            _expr = _format(result);
            widget.onResult(result);
          }
        case '.':
          final segment = _expr.split(RegExp(r'[+−×÷]')).last;
          if (!segment.contains('.')) {
            _expr +=
                _expr.isEmpty || _isOperator(_expr[_expr.length - 1])
                    ? '0.'
                    : '.';
          }
        default:
          if (_isOperator(key) &&
              _expr.isNotEmpty &&
              _isOperator(_expr[_expr.length - 1])) {
            // Replace a trailing operator instead of stacking them.
            _expr = _expr.substring(0, _expr.length - 1) + key;
          } else {
            _expr += key;
          }
      }
    });
  }

  /// "1 234.50" → "1234.5", whole numbers lose the decimal part.
  String _format(double value) {
    if (value.truncateToDouble() == value) return value.toStringAsFixed(0);
    return value
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  /// Evaluates expressions like "120+35×2" with × ÷ binding tighter than
  /// + −. Supports a leading (or post-operator) unary minus. Returns null
  /// when the expression is incomplete or invalid (incl. division by zero).
  double? _evaluate(String expr) {
    final s = expr
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll('−', '-')
        .replaceAll(' ', '');
    if (s.isEmpty) return null;

    final values = <double>[];
    final ops = <String>[];
    final buf = StringBuffer();
    var lastWasOperator = true; // true at start → leading "-" is unary

    bool pushNumber() {
      if (buf.isEmpty) return false;
      final n = double.tryParse(buf.toString());
      buf.clear();
      if (n == null) return false;
      // Resolve × and ÷ immediately (higher precedence).
      if (ops.isNotEmpty && (ops.last == '*' || ops.last == '/')) {
        final op = ops.removeLast();
        final left = values.removeLast();
        if (op == '/' && n == 0) return false;
        values.add(op == '*' ? left * n : left / n);
      } else {
        values.add(n);
      }
      return true;
    }

    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      final code = ch.codeUnitAt(0);
      if ((code >= 48 && code <= 57) || ch == '.') {
        buf.write(ch);
        lastWasOperator = false;
      } else if (ch == '+' || ch == '-' || ch == '*' || ch == '/') {
        if (ch == '-' && lastWasOperator) {
          buf.write(ch); // unary minus
          continue;
        }
        if (!pushNumber()) return null;
        ops.add(ch);
        lastWasOperator = true;
      } else {
        return null;
      }
    }
    if (!pushNumber()) return null; // trailing operator

    // Only + and − remain at this point.
    var result = values.first;
    for (var i = 0; i < ops.length; i++) {
      result += ops[i] == '+' ? values[i + 1] : -values[i + 1];
    }
    if (result.isInfinite || result.isNaN) return null;
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Brand accents that stay readable on both themes.
    final accent = isDark ? kGold : kEmerald;
    final accentSoft =
        isDark ? const Color(0xFFE8C766) : const Color(0xFF8a6d1c);
    final preview = _evaluate(_expr);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kGold.withValues(alpha: 0.45)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.14 : 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _expr.isEmpty ? '0' : _expr,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (preview != null && _expr.isNotEmpty)
                  Text(
                    '= ${_format(preview)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: accentSoft,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tr(context, 'calc_hint'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1.3,
            ),
            itemCount: _keys.length,
            itemBuilder: (context, i) => _CalcKey(
              label: _keys[i],
              onTap: () => _press(_keys[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalcKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _CalcKey({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isEquals = label == '=';
    final isOperator =
        label == '+' || label == '−' || label == '×' || label == '÷';
    final isUtility = label == 'C' || label == '⌫';
    final bg = isEquals
        ? kEmerald
        : isOperator
            ? kGold.withValues(alpha: 0.22)
            : isUtility
                ? theme.colorScheme.errorContainer
                : theme.colorScheme.surfaceContainerHighest;
    final fg = isEquals
        ? Colors.white
        : isOperator
            ? (isDark
                ? const Color(0xFFE8C766)
                : const Color(0xFF8a6d1c))
            : isUtility
                ? theme.colorScheme.onErrorContainer
                : theme.colorScheme.onSurface;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: isOperator
              ? Border.all(color: kGold.withValues(alpha: 0.65))
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      ),
    );
  }
}
