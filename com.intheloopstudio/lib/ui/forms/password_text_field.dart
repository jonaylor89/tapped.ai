import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class PasswordTextField extends StatefulWidget {
  const PasswordTextField({
    super.key,
    this.onSaved,
    this.onChanged,
    this.onSubmitted,
    this.labelText = 'password',
    this.textInputAction = TextInputAction.done,
  });

  final void Function(String?)? onSaved;
  final void Function(String?)? onChanged;
  final void Function(String)? onSubmitted;
  final String labelText;
  final TextInputAction textInputAction;

  @override
  State<PasswordTextField> createState() => _PasswordTextFieldState();
}

class _PasswordTextFieldState extends State<PasswordTextField> {
  bool _hidePassword = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassTextField(
      hintText: widget.labelText,
      prefixIcon: CupertinoIcons.lock,
      obscureText: _hidePassword,
      autocorrect: false,
      textInputAction: widget.textInputAction,
      validator: (input) {
        if ((input ?? '').trim().length < 8) {
          return 'password must be at least 8 characters';
        }
        return null;
      },
      onChanged: (input) => widget.onChanged?.call(input),
      onSubmitted: widget.onSubmitted,
      suffix: GlassPressable(
        haptics: false,
        semanticsLabel: _hidePassword ? 'show password' : 'hide password',
        onPressed: () => setState(() => _hidePassword = !_hidePassword),
        child: Padding(
          padding: const EdgeInsets.all(TappedSpacing.sm),
          child: Icon(
            _hidePassword ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}
