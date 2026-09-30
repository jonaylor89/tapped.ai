import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class ArtistNameTextField extends StatelessWidget {
  const ArtistNameTextField({
    super.key,
    this.onSaved,
    this.onChanged,
    this.initialValue,
  });

  final void Function(String?)? onSaved;
  final void Function(String?)? onChanged;
  final String? initialValue;

  @override
  Widget build(BuildContext context) {
    return GlassTextField(
      initialValue: initialValue,
      hintText: 'performer name (e.g. Doja Cat)',
      prefixIcon: CupertinoIcons.music_mic,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.done,
      validator: (input) {
        if ((input ?? '').trim().isEmpty) {
          return 'please enter a valid name';
        }
        return null;
      },
      onChanged: (input) {
        if (input.isEmpty) return;
        onChanged?.call(input.trim());
      },
    );
  }
}
