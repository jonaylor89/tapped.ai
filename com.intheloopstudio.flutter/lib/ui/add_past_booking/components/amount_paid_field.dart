import 'package:currency_text_input_formatter/currency_text_input_formatter.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/ui/add_past_booking/add_past_booking_cubit.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class AmountPaidField extends StatelessWidget {
  AmountPaidField({super.key});

  final _formatter = CurrencyTextInputFormatter.simpleCurrency(
    locale: 'en_US',
    decimalDigits: 2,
  );

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AddPastBookingCubit, AddPastBookingState>(
      builder: (context, state) {
        return GlassQuestion(
          title: 'how much did you make?',
          caption: 'optional · only you see the exact number',
          child: GlassTextField(
            initialValue: _formatter.format.format(state.amountPaid),
            keyboardType: TextInputType.number,
            prefixIcon: CupertinoIcons.money_dollar,
            hintText: r'$0.00',
            inputFormatters: <TextInputFormatter>[_formatter],
            onChanged: (input) {
              final value = _formatter.getUnformattedValue().toDouble();
              final usdValue = (value * 100).toInt();
              context.read<AddPastBookingCubit>().amountPaidChanged(usdValue);
            },
          ),
        );
      },
    );
  }
}
