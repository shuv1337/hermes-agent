import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/features/bots/bots_screen.dart';

HermesBotProfile _bot(String name, {String? group}) {
  return HermesBotProfile.fromJson({
    'name': name,
    'ui_meta': {
      'hermes-bots': {'title': name, 'group': ?group},
    },
  });
}

void main() {
  test('bot roster keeps ungrouped first and sorts group sections', () {
    final sections = botRosterSections([
      _bot('one'),
      _bot('fitness', group: 'Health and Fitness'),
      _bot('work', group: 'Admin'),
      _bot('sleep', group: 'Health and Fitness'),
    ]);

    expect(sections.map((section) => section.group), [
      null,
      'Admin',
      'Health and Fitness',
    ]);
    expect(sections[2].bots.map((bot) => bot.name), ['fitness', 'sleep']);
  });
}
