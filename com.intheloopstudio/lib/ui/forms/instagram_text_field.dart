import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class InstagramTextField extends StatelessWidget {
  const InstagramTextField({
    super.key,
    this.onChanged,
    this.initialValue,
  });

  final void Function(String)? onChanged;
  final String? initialValue;

  @override
  Widget build(BuildContext context) {
    return GlassTextField(
      label: 'handle',
      hintText: '@username',
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_\.\-\$]')),
      ],
      initialValue: initialValue,
      autocorrect: false,
      onChanged: (input) {
        onChanged?.call(input.trim().toLowerCase());
      },
    );
  }
}
