import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart';

class ThreadView extends StatelessWidget {
  const ThreadView({super.key, this.parent});

  final Message? parent;

  @override
  Widget build(BuildContext context) {
    return GlassAmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: StreamThreadHeader(
          parent: parent!,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Column(
          children: [
            Expanded(
              child: StreamMessageListView(
                parentMessage: parent,
              ),
            ),
            const StreamMessageInput(),
          ],
        ),
      ),
    );
  }
}
