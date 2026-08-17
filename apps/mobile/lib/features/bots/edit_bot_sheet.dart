import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/health/apple_health_sync.dart';
import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/features/bots/bot_advanced_editor.dart';
import 'package:hermes_mobile/features/bots/bot_avatar.dart';
import 'package:hermes_mobile/features/bots/create_bot_sheet.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

Future<bool> showEditBotSheet(
  BuildContext context, {
  required HermesBotProfile bot,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _EditBotSheet(bot: bot),
  ).then((saved) => saved ?? false);
}

class _EditBotSheet extends ConsumerStatefulWidget {
  const _EditBotSheet({required this.bot});

  final HermesBotProfile bot;

  @override
  ConsumerState<_EditBotSheet> createState() => _EditBotSheetState();
}

class _EditBotSheetState extends ConsumerState<_EditBotSheet> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late String _shape;
  late String _color;
  late bool _usePhoto;
  late bool _healthCoach;
  final _advanced = BotAdvancedController.edit();
  Uint8List? _pickedAvatar;
  bool _avatarChanged = false;
  bool _busy = false;
  String? _error;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.bot.title ?? '');
    _description = TextEditingController(text: widget.bot.description ?? '');
    _shape = widget.bot.shape ?? 'circle';
    _color = widget.bot.color ?? '#f97316';
    _usePhoto = widget.bot.usesImageAvatar && widget.bot.hasAvatar;
    final rawUi = widget.bot.raw['ui_meta'];
    final rawMeta = rawUi is Map ? rawUi['hermes-bots'] : null;
    _healthCoach = rawMeta is Map && rawMeta['healthCoach'] == true;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _advanced.dispose();
    super.dispose();
  }

  HermesBotProfile _previewBot(String shape, String color) {
    return HermesBotProfile.fromJson({
      'name': widget.bot.name,
      'ui_meta': {
        'hermes-bots': {
          'title': _title.text.trim(),
          'shape': shape,
          'color': color,
          'imageKind': 'shape',
        },
      },
    });
  }

  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 2000000) {
        throw StateError('Image is larger than the server’s 2 MB limit');
      }
      final supported = _isPng(bytes) || _isJpeg(bytes) || _isWebp(bytes);
      if (!supported) {
        throw StateError('Choose a PNG, JPEG, or WebP image');
      }
      if (!mounted) return;
      setState(() {
        _pickedAvatar = bytes;
        _usePhoto = true;
        _avatarChanged = true;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = context.l10n.couldNotPickImage('$error'));
    }
  }

  void _selectShape(String shape) {
    setState(() {
      _shape = shape;
      _usePhoto = false;
      _pickedAvatar = null;
      _avatarChanged = widget.bot.hasAvatar;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final sync = ref.read(sessionSyncProvider);
    if (sync == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_healthCoach) {
        final profile = ref.read(connectionProfileProvider).value;
        final dashboard = ref.read(dashboardClientProvider);
        if (profile == null || dashboard == null) {
          throw StateError('Connect to your Hermes gateway first');
        }
        final health = AppleHealthSync(
          gatewayId: profile.id,
          dashboard: dashboard,
        );
        if (!await health.isEnabled &&
            !await health.requestReadAuthorization()) {
          throw StateError('Apple Health read access was not granted');
        }
        await health.sync(initial: true);
      }
      await sync.updateBot(
        bot: widget.bot,
        title: _title.text,
        description: _description.text,
        shape: _shape,
        color: _color,
        usePhoto: _usePhoto,
        avatarBytes: _pickedAvatar,
        avatarChanged: _avatarChanged,
        healthCoach: _healthCoach,
        soul: _advanced.dirtySoul ? _advanced.soul.text : null,
        model: _advanced.dirtyModel ? _advanced.model : '',
        provider: _advanced.dirtyModel ? _advanced.provider : '',
        disabledSkills: _advanced.disabledSkills,
        enabledToolsets: _advanced.enabledToolsets,
        enabledMcpServers: _advanced.enabledMcpServers,
      );
      ref.invalidate(botAvatarProvider(widget.bot.name));
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.editBotTitle, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                l10n.botHandleImmutable(widget.bot.handle),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                ),
              ),
              const SizedBox(height: 18),
              Center(child: _avatarPreview()),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _pickAvatar(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(l10n.photoLibrary),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _pickAvatar(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(l10n.camera),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _title,
                enabled: !_busy,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: l10n.title),
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _description,
                enabled: !_busy,
                minLines: 2,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: l10n.botDescriptionLabel,
                ),
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
              ),
              const SizedBox(height: 20),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _healthCoach,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _healthCoach = value),
                secondary: const Icon(Icons.favorite_outline),
                title: const Text('Health Coach'),
                subtitle: const Text(
                  'Allow this bot to query Apple Health data synced privately from this iPhone.',
                ),
              ),
              BotAdvancedEditor(
                controller: _advanced,
                profile: widget.bot.name,
                profileNames: const {},
                enabled: !_busy,
              ),
              const SizedBox(height: 10),
              Text(l10n.botAppearanceLabel, style: theme.textTheme.titleSmall),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final shape in botShapes)
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _busy ? null : () => _selectShape(shape),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 52,
                        height: 52,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: !_usePhoto && _shape == shape
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline.withValues(
                                    alpha: 0.3,
                                  ),
                            width: !_usePhoto && _shape == shape ? 2 : 1,
                          ),
                        ),
                        child: BotAvatar(
                          bot: _previewBot(shape, _color),
                          size: 40,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final color in botColors)
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _busy
                          ? null
                          : () => setState(() {
                              _color = color;
                              _usePhoto = false;
                              _pickedAvatar = null;
                              _avatarChanged = widget.bot.hasAvatar;
                            }),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(
                            int.parse(color.substring(1), radix: 16) |
                                0xFF000000,
                          ),
                          border: Border.all(
                            color: !_usePhoto && _color == color
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.outline.withValues(
                                    alpha: 0.35,
                                  ),
                            width: !_usePhoto && _color == color ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_busy ? l10n.savingBot : l10n.save),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarPreview() {
    if (_usePhoto && _pickedAvatar != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.memory(
          _pickedAvatar!,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
        ),
      );
    }
    if (_usePhoto) return BotAvatar(bot: widget.bot, size: 72);
    return BotAvatar(bot: _previewBot(_shape, _color), size: 72);
  }
}

bool _isPng(Uint8List bytes) =>
    bytes.length >= 8 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4e &&
    bytes[3] == 0x47;

bool _isJpeg(Uint8List bytes) =>
    bytes.length >= 3 &&
    bytes[0] == 0xff &&
    bytes[1] == 0xd8 &&
    bytes[2] == 0xff;

bool _isWebp(Uint8List bytes) =>
    bytes.length >= 12 &&
    String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
    String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
