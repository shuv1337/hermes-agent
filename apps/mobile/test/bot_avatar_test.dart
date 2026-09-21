import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/features/bots/bot_avatar.dart';

void main() {
  testWidgets('shape avatar is drawn from server metadata', (tester) async {
    final bot = HermesBotProfile.fromJson({
      'name': 'techno',
      'ui_meta': {
        'hermes-bots': {
          'title': 'Senior cat wrangler',
          'shape': 'hexagon',
          'color': '#f97316',
          'imageKind': 'shape',
        },
      },
    });

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: Scaffold(body: BotAvatar(bot: bot)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
