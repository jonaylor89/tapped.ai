import 'package:email_validator/email_validator.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class EmailTextField extends StatelessWidget {
  const EmailTextField({
    super.key,
    this.onChanged,
    this.labelText = 'email',
    this.textInputAction = TextInputAction.next,
  });

  final void Function(String?)? onChanged;
  final String labelText;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    return GlassTextField(
      hintText: labelText,
      keyboardType: TextInputType.emailAddress,
      textInputAction: textInputAction,
      autocorrect: false,
      validator: (value) => EmailValidator.validate(value ?? '')
          ? null
          : 'please enter a valid email',
      onChanged: (input) => onChanged?.call(input),
    );
  }
}
