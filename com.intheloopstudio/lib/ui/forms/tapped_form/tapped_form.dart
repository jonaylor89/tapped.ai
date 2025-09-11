import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:intheloopapp/ui/themes.dart';
import 'package:intheloopapp/utils/app_logger.dart';

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

  int get _numQuestions => widget.questions.length;

  Widget get _currQuestion => widget.questions[_index].child;

  FutureOr<bool> Function() get _currValidator =>
      widget.questions[_index].validator ?? () => true;

  Widget _buildNextButton(bool? isValid) {
    final isLast = _index == _numQuestions - 1;
    final localOnNext = widget.questions[_index].onNext;

    if (isValid == null) {
      return const CupertinoButton(
        onPressed: null,
        child: CupertinoActivityIndicator(),
      );
    }

    return switch (isLast) {
      false => CupertinoButton(
          onPressed: isValid
              ? () async {
                  await EasyLoading.show();
                  await localOnNext?.call();
                  await widget.onNext?.call(_index);

                  setState(() {
                    _index++;
                  });
                  await EasyLoading.dismiss();
                }
              : null,
          borderRadius: BorderRadius.circular(12),
          color: tappedAccent,
          child: Text(
            'next',
            style: TextStyle(
              color: isValid ? Colors.white : Colors.black,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      true => CupertinoButton(
          onPressed: isValid
              ? () {
                  try {
                    widget.onSubmit?.call();
                  } catch (e, s) {
                    logger.error(
                      'error submitting form',
                      error: e,
                      stackTrace: s,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: Colors.red,
                        content: Text('something went wrong'),
                      ),
                    );
                  }
                }
              : null,
          borderRadius: BorderRadius.circular(12),
          color: tappedAccent,
          child: Text(
            'finish',
            style: TextStyle(
              color: isValid ? Colors.white : Colors.black,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final numQuestions = widget.questions.length;

    if (widget.questions.isEmpty) {
      return const Center(
        child: Text('No questions'),
      );
    }

    const horizPadding = 16.0;
    const segmentPadding = 4;
    final segmentWidth =
        (MediaQuery.of(context).size.width - (horizPadding * 2)) /
            numQuestions -
            (segmentPadding * 2);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: horizPadding,
            vertical: 12,
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: widget.questions.map((e) {
                  return SizedBox(
                    width: segmentWidth,
                    height: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: widget.questions.indexOf(e) <= _index
                            ? theme.colorScheme.primary
                            : theme.colorScheme.primary.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }).toList(),
              ),
              Expanded(
                child: Center(
                  child: _currQuestion,
                ),
              ),
              const SizedBox(height: 16),
              FutureBuilder(
                future: Future.value(_currValidator()),
                builder: (context, snapshot) {
                  final isValid = snapshot.data;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_index != 0)
                        CupertinoButton(
                          onPressed: () {
                            setState(() {
                              _index--;
                            });
                            widget.onPrevious?.call(_index);
                          },
                          child: const Text(
                            'back',
                          ),
                        ),
                      if (_index == 0 && widget.cancelButton)
                        CupertinoButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: const Text(
                            'cancel',
                            style: TextStyle(
                              color: Colors.red,
                            ),
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                      _buildNextButton(isValid),
                    ],
                  );
                },
              ),
            ],
          ),
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
