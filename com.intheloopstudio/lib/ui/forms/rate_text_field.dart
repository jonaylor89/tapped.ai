import 'package:currency_text_input_formatter/currency_text_input_formatter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RateTextField extends StatelessWidget {
  RateTextField({
    super.key,
    this.onChanged,
    this.onSubmitted,
    this.initialValue = 0,
  });

  final void Function(int)? onChanged;
  final void Function(int)? onSubmitted;
  final int initialValue;

  final _formatter = CurrencyTextInputFormatter.simpleCurrency(
    locale: 'en_US',
    decimalDigits: 2,
    enableNegative: false,
  );

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: _formatter.format.format(initialValue),
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.attach_money),
        labelText: 'Price',
        // prefixText: r'$ ',
      ),
      inputFormatters: <TextInputFormatter>[_formatter],
      keyboardType: TextInputType.number,
      onFieldSubmitted: (input) {
        final value = _formatter.getUnformattedValue().toDouble();
        final usdValue = (value * 100).toInt();

        onSubmitted?.call(usdValue);
      },
      onChanged: (input) {
        final value = _formatter.getUnformattedValue().toDouble();
        final usdValue = (value * 100).toInt();

        onChanged?.call(usdValue);
      },
    );
  }
}
