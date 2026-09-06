import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_tokens.dart';

/// Large -- / value / ++ stepper with hold-to-repeat, bounds clamping,
/// tap-the-value-to-type entry (digits only, hard-clamped), optional
/// quick-value chips, and an explicit "Not available" escape.
class StepperTiles extends StatelessWidget {
  const StepperTiles({
    super.key,
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
    this.decimals = 0,
    this.quickValues = const [],
    this.canBeMissing = false,
    this.missing = false,
    this.onMissing,
    this.manualMin,
    this.manualMax,
  });

  /// Current value (display only when [missing]).
  final double value;
  final ValueChanged<double> onChanged;

  /// Stepper (button/quick-chip) bounds.
  final double min;
  final double max;
  final double step;
  final String unit;
  final int decimals;
  final List<double> quickValues;
  final bool canBeMissing;
  final bool missing;
  final VoidCallback? onMissing;

  /// Hard bounds for typed entry; wider than the stepper range so a measured
  /// abnormal value can still be recorded without risking the pipeline.
  /// Defaults to [min]/[max] when not provided.
  final double? manualMin;
  final double? manualMax;

  double get _minEntry => manualMin ?? min;
  double get _maxEntry => manualMax ?? max;

  String get _display {
    if (missing) return 'Not measured';
    if (decimals > 0) return value.toStringAsFixed(decimals);
    return value.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _stepButton(context, false)),
            Expanded(flex: 2, child: _valueDisplay(context)),
            Expanded(child: _stepButton(context, true)),
          ],
        ),
        if (quickValues.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: AppMetrics.gap,
            runSpacing: AppMetrics.gap,
            alignment: WrapAlignment.center,
            children: [
              for (final q in quickValues)
                ActionChip(
                  label: Text(
                      '${q == q.roundToDouble() ? q.toInt().toString() : q.toString()} $unit'),
                  onPressed: () => onChanged(q),
                  key: ValueKey('quick-$q'),
                ),
            ],
          ),
        ],
        if (canBeMissing) ...[
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onMissing,
            style: TextButton.styleFrom(
              minimumSize: const Size(56, 52),
              foregroundColor: AppColors.textSubdued,
            ),
            icon: const Icon(Icons.remove_circle_outline),
            label: Text(
              missing ? 'Unmark as missing' : 'I cannot measure this',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Tap the number to type it.',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSubdued.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _valueDisplay(BuildContext context) {
    final background = missing ? AppColors.surface : AppColors.teal800;
    return Semantics(
      button: true,
      label: missing ? 'Enter value' : 'Value $_display $unit, tap to edit',
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: const ValueKey('valueDisplay'),
          onTap: () => _promptNumberInput(context),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: AppMetrics.minTouch + 16,
            alignment: Alignment.center,
            margin: const EdgeInsets.symmetric(horizontal: AppMetrics.gap),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  '$_display $unit',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: missing
                        ? AppColors.textSubdued
                        : AppColors.textPrimary,
                  ),
                ),
                if (missing)
                  const Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: EdgeInsets.only(top: 8, right: 10),
                      child: Icon(Icons.edit, size: 16, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _promptNumberInput(BuildContext context) async {
    final submitted = await showDialog<String>(
      context: context,
      builder: (_) => _NumberInputDialog(
        unit: unit,
        decimals: decimals,
        initialText: missing ? '' : _display,
        minEntry: _minEntry.round(),
        maxEntry: _maxEntry.round(),
      ),
    );
    if (submitted == null) return;
    final parsed = double.tryParse(submitted.trim());
    if (parsed == null) return;
    onChanged(parsed.clamp(_minEntry, _maxEntry).toDouble());
  }

  Widget _stepButton(BuildContext context, bool increment) {
    final icon = increment ? Icons.add : Icons.remove;
    return Semantics(
      button: true,
      label: increment ? 'Increase' : 'Decrease',
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _step(increment),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: AppMetrics.minTouch + 16,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Icon(icon, size: 34, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }

  void _step(bool increment) {
    final next = increment ? value + step : value - step;
    onChanged(next.clamp(min, max).toDouble());
  }
}

/// Digits-only number entry dialog shown when the value box is tapped.
/// Owns its [TextEditingController] so it is disposed with the route
/// (i.e. only after the dialog's closing animation finishes).
class _NumberInputDialog extends StatefulWidget {
  const _NumberInputDialog({
    required this.unit,
    required this.decimals,
    required this.initialText,
    required this.minEntry,
    required this.maxEntry,
  });

  final String unit;
  final int decimals;
  final String initialText;
  final int minEntry;
  final int maxEntry;

  @override
  State<_NumberInputDialog> createState() => _NumberInputDialogState();
}

class _NumberInputDialogState extends State<_NumberInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<TextInputFormatter> get _formatters => [
        if (widget.decimals > 0)
          TextInputFormatter.withFunction(
            (oldValue, newValue) => RegExp(r'^\d{0,3}(\.\d{0,2})?$')
                .hasMatch(newValue.text)
                ? newValue
                : oldValue,
          )
        else
          FilteringTextInputFormatter.digitsOnly,
      ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter value'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(
          decimal: widget.decimals > 0,
        ),
        inputFormatters: _formatters,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        decoration: InputDecoration(
          labelText: widget.unit,
          hintText: 'Numbers only (${widget.minEntry}–${widget.maxEntry})',
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save() {
    Navigator.pop(context, _controller.text.trim());
  }
}