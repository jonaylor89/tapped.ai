import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class SearchTextField extends StatelessWidget {
  const SearchTextField({
    required this.controller,
    this.onChanged,
    this.onTap,
    this.hintText = 'search conversations',
    this.showCloseButton = true,
    super.key,
  });
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String hintText;
  final VoidCallback? onTap;
  final bool showCloseButton;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GlassMetrics.edgeInset,
        TappedSpacing.sm,
        GlassMetrics.edgeInset,
        TappedSpacing.sm,
      ),
      child: GlassSearchField(
        controller: controller,
        onChanged: onChanged,
        onTap: onTap,
        hintText: hintText,
        trailing: showCloseButton
            ? GlassPressable(
                haptics: false,
                semanticsLabel: 'clear search',
                onPressed: () {
                  controller?.clear();
                  FocusScope.of(context).unfocus();
                },
                child: const Padding(
                  padding: EdgeInsets.all(TappedSpacing.sm),
                  child: Icon(Icons.close, size: 18),
                ),
              )
            : null,
      ),
    );
  }
}
