import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';

class EmailTextField extends StatelessWidget {
  const EmailTextField({
    super.key,
    this.onChanged,
    this.labelText = 'email',
  });

  final void Function(String?)? onChanged;
  final String labelText;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          18,
        ),
        child: TextFormField(
          decoration: InputDecoration.collapsed(
            // prefixIcon: const Icon(Icons.lock),
            // labelText: labelText,
            hintText: labelText,
          ),
          keyboardType: TextInputType.emailAddress,
          validator: (value) => EmailValidator.validate(value ?? '')
              ? null
              : 'please enter a valid email',
          onChanged: (input) async {
            onChanged?.call(input);
          },
        ),
      ),
    );
  }
}
