import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/domains/models/label.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class LabelFormView extends StatefulWidget {
  const LabelFormView({
    required this.onChange,
    required this.initialValue,
    super.key,
  });

  final void Function(String?) onChange;
  final String? initialValue;

  @override
  State<LabelFormView> createState() => _LabelFormViewState();
}

class _LabelFormViewState extends State<LabelFormView> {
  String _groupValue = '';

  @override
  void initState() {
    super.initState();
    _groupValue = widget.initialValue ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassPage(
      title: 'label',
      padding: EdgeInsets.zero,
      slivers: [
        SliverToBoxAdapter(
          child: GlassSection(
            children: [
              for (final label in labels)
                GlassListTile(
                  title: label,
                  showChevron: false,
                  trailing: label == _groupValue
                      ? Icon(
                          CupertinoIcons.checkmark_alt,
                          color: theme.colorScheme.primary,
                          size: 20,
                        )
                      : null,
                  onTap: () {
                    setState(() {
                      _groupValue = label;
                    });
                    widget.onChange.call(label);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
