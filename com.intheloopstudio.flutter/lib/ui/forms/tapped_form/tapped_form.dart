import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/utils/app_logger.dart';

/// Multi-step questionnaire. One question fills the screen at a time over an
/// ambient glass backdrop; a segmented capsule at the top tracks progress and
/// back/next float in a glass bottom bar. Steps slide in from the direction
/// of travel.
class TappedForm extends StatefulWidget {
  const TappedForm({
    required this.questions,
    this.cancelButton = false,
    this.onNext,
    this.onPrevious,
    this.onSubmit,
    super.key,
  });

  final List<FormQuestion> questions;
  final bool cancelButton;
  final FutureOr<void> Function(int)? onNext;
  final FutureOr<void> Function(int)? onPrevious;
  final FutureOr<void> Function()? onSubmit;

  @override
  State<TappedForm> createState() => _TappedFormState();
}

class _TappedFormState extends State<TappedForm> {
  int _index = 0;
  bool _forward = true;

  int get _numQuestions => widget.questions.length;

  Widget get _currQuestion => widget.questions[_index].child;

  FutureOr<bool> Function() get _currValidator =>
      widget.questions[_index].validator ?? () => true;

  Future<void> _next() async {
    final localOnNext = widget.questions[_index].onNext;
    await EasyLoading.show();
    await localOnNext?.call();
    await widget.onNext?.call(_index);
    if (mounted) {
      setState(() {
        _forward = true;
        _index++;
      });
    }
    await EasyLoading.dismiss();
  }

  void _submit() {
    try {
      widget.onSubmit?.call();
    } catch (e, s) {
      logger.error('error submitting form', error: e, stackTrace: s);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
          content: Text('something went wrong'),
        ),
      );
    }
  }

  Widget _buildNextButton(bool? isValid) {
    final isLast = _index == _numQuestions - 1;

    if (isValid == null) {
      return const GlassButton.primary(
        label: 'next',
        isLoading: true,
        onPressed: null,
      );
    }

    return GlassButton.primary(
      label: isLast ? 'finish' : 'next',
      icon: isLast ? CupertinoIcons.checkmark_alt : CupertinoIcons.arrow_right,
      onPressed: !isValid
          ? null
          : isLast
          ? _submit
          : _next,
    );
  }

  Widget _progress(ThemeData theme) {
    return Row(
      children: [
        for (var i = 0; i < _numQuestions; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: AnimatedContainer(
              duration: GlassMotion.reveal,
              curve: GlassMotion.ease,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: i <= _index
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.15),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.questions.isEmpty) {
      return const GlassAmbientBackground(
        child: Center(child: Text('No questions')),
      );
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      resizeToAvoidBottomInset: false,
      body: GlassAmbientBackground(
        child: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: GlassMetrics.edgeInset,
                        vertical: TappedSpacing.md,
                      ),
                      child: Row(
                        children: [
                          Expanded(child: _progress(theme)),
                          const SizedBox(width: TappedSpacing.md),
                          Text(
                            '${_index + 1}/$_numQuestions',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.55,
                              ),
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: GlassMotion.release,
                        switchInCurve: GlassMotion.ease,
                        switchOutCurve: GlassMotion.ease,
                        transitionBuilder: (child, animation) {
                          final offset = Tween<Offset>(
                            begin: Offset(_forward ? 0.08 : -0.08, 0),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: offset,
                              child: child,
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey(_index),
                          child: Padding(
                            padding: EdgeInsets.only(
                              bottom:
                                  GlassMetrics.bottomBarClearance +
                                  MediaQuery.viewInsetsOf(context).bottom,
                            ),
                            child: Center(child: _currQuestion),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.viewInsetsOf(context).bottom,
              child: GlassBottomBar(
                child: FutureBuilder(
                  future: Future.value(_currValidator()),
                  builder: (context, snapshot) {
                    final isValid = snapshot.data;
                    return Row(
                      children: [
                        if (_index != 0)
                          GlassButton(
                            label: 'back',
                            icon: CupertinoIcons.arrow_left,
                            onPressed: () {
                              setState(() {
                                _forward = false;
                                _index--;
                              });
                              widget.onPrevious?.call(_index);
                            },
                          )
                        else if (widget.cancelButton)
                          GlassButton.plain(
                            label: 'cancel',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        const Spacer(),
                        _buildNextButton(isValid),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FormQuestion {
  const FormQuestion({
    required this.child,
    this.validator,
    this.onNext,
  });

  final Widget child;
  final FutureOr<bool> Function()? validator;
  final FutureOr<void> Function()? onNext;
}
