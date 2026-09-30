import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class InstagramFollowersTextField extends StatelessWidget {
  const InstagramFollowersTextField({
    this.initialValue,
    this.onChanged,
    super.key,
  });

  final int? initialValue;
  final void Function(int)? onChanged;

  @override
  Widget build(BuildContext context) {
    final iVal = initialValue ?? 0;
    return GlassTextField(
      label: 'followers',
      hintText: '0',
      initialValue: iVal.toString(),
      keyboardType: TextInputType.number,
      onChanged: (input) {
        final value = double.tryParse(input) ?? 0;
        onChanged?.call(value.toInt());
      },
    );
  }
}
