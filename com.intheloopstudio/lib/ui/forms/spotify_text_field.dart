import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class SpotifyTextField extends StatelessWidget {
  const SpotifyTextField({
    super.key,
    this.onChanged,
    this.initialValue,
  });

  final void Function(String)? onChanged;
  final String? initialValue;

  @override
  Widget build(BuildContext context) {
    return GlassTextField(
      initialValue: initialValue,
      label: 'spotify artist url',
      prefixIcon: FontAwesomeIcons.spotify,
      hintText: 'https://open.spotify.com/artist/…',
      keyboardType: TextInputType.url,
      autocorrect: false,
      onChanged: (input) => onChanged?.call(input),
    );
  }
}
