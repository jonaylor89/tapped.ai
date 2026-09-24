import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';

class DownForMainenanceView extends StatelessWidget {
  const DownForMainenanceView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: <Color>[
              TappedColors.backgroundDark,
              TappedColors.accent,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/icon_512.png', scale: 5),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  'Tapped is down for maintenance \n👷‍♂️👷‍♀️',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: TappedColors.textOnImage,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
