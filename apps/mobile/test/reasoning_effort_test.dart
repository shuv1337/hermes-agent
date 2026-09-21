import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_mobile/core/config/reasoning_effort.dart';
import 'package:hermes_mobile/core/network/dashboard_client.dart';

void main() {
  group('Desktop model controls', () {
    test('uses a request parameter when the model advertises Fast', () {
      final control = resolveFastControl('gpt-5', ['gpt-5'], true, false);

      expect(control.kind, FastControlKind.parameter);
      expect(control.on, isFalse);
    });

    test('uses a -fast sibling as a variant toggle', () {
      final off = resolveFastControl(
        'model',
        ['model', 'model-fast'],
        false,
        false,
      );
      final on = resolveFastControl(
        'model-fast',
        ['model', 'model-fast'],
        false,
        false,
      );

      expect(off.kind, FastControlKind.variant);
      expect(off.fastId, 'model-fast');
      expect(off.on, isFalse);
      expect(on.baseId, 'model');
      expect(on.on, isTrue);
    });

    test('does not expose an orphan -fast model as a toggle', () {
      final families = collapseModelFamilies(['orphan-fast', 'plain']);

      expect(families.map((f) => f.id), ['orphan-fast', 'plain']);
      expect(families.first.fastId, isNull);
      expect(
        resolveFastControl('orphan-fast', ['orphan-fast'], false, false).kind,
        FastControlKind.none,
      );
    });
  });

  group('model capability defaults', () {
    test('repairs a stale provider when a model moved providers', () {
      const options = ModelOptionsResult(
        providers: [
          ModelOptionProvider(
            slug: 'openrouter',
            name: 'OpenRouter',
            models: ['other'],
          ),
          ModelOptionProvider(
            slug: 'nous',
            name: 'Nous Portal',
            models: ['openai/gpt-5.6-sol'],
          ),
        ],
      );

      expect(
        providerForModel(
          options,
          'openai/gpt-5.6-sol',
          preferred: 'openrouter',
        ),
        'nous',
      );
      expect(
        providerForModel(options, 'other', preferred: 'openrouter'),
        'openrouter',
      );
    });

    test('keeps Thinking visible for an older payload with no map', () {
      const provider = ModelOptionProvider(
        slug: 'provider',
        name: 'Provider',
        models: ['model'],
      );

      expect(provider.capsFor('model').reasoning, isTrue);
      expect(provider.capsFor('model').fast, isFalse);
    });

    test('treats an explicit map omission as unsupported', () {
      const provider = ModelOptionProvider(
        slug: 'provider',
        name: 'Provider',
        models: ['model', 'other'],
        capabilities: {
          'model': ModelCapabilities(fast: true, reasoning: false),
        },
      );

      expect(provider.capsFor('model').fast, isTrue);
      expect(provider.capsFor('model').reasoning, isFalse);
      expect(provider.capsFor('other').fast, isFalse);
      expect(provider.capsFor('other').reasoning, isFalse);
    });

    test('fast model variant inherits its base model capabilities', () {
      const provider = ModelOptionProvider(
        slug: 'provider',
        name: 'Provider',
        models: ['reasoner', 'reasoner-fast'],
        capabilities: {
          'reasoner': ModelCapabilities(reasoning: true, fast: false),
        },
      );

      expect(provider.capsFor('reasoner-fast').reasoning, isTrue);
      expect(provider.capsFor('reasoner-fast').fast, isFalse);
    });
  });
}
