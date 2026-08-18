import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/core/sync/session_sync_repository.dart';
import 'package:hermes_mobile/features/bots/bot_avatar.dart';

const botShapes = [
  'circle',
  'squircle',
  'pill',
  'triangle',
  'hexagon',
  'cloud',
  'drop',
];

const botColors = [
  '#f5f5f4',
  '#8d6748',
  '#ef4444',
  '#f97316',
  '#14b8a6',
  '#38bdf8',
  '#3b40c8',
  '#8b5cf6',
  '#ec4899',
  '#9ca3af',
];

final _petThumbQueue = Queue<Future<void> Function()>();
final _petThumbCache = <String, Future<Uint8List?>>{};
int _petThumbActive = 0;

void _pumpPetThumbs() {
  while (_petThumbActive < 4 && _petThumbQueue.isNotEmpty) {
    _petThumbActive++;
    final job = _petThumbQueue.removeFirst();
    unawaited(
      job().whenComplete(() {
        _petThumbActive--;
        _pumpPetThumbs();
      }),
    );
  }
}

Future<T> _limitPetThumb<T>(Future<T> Function() task) {
  final completer = Completer<T>();
  _petThumbQueue.add(() async {
    try {
      completer.complete(await task());
    } catch (error, stack) {
      completer.completeError(error, stack);
    }
  });
  _pumpPetThumbs();
  return completer.future;
}

Future<Uint8List?> _petThumb(SessionSyncRepository sync, _PetChoice pet) =>
    _petThumbCache.putIfAbsent(
      '${pet.slug}|${pet.url}',
      () => _limitPetThumb(() async {
        final result = await sync.gatewayRequest('pet.thumb', {
          'slug': pet.slug,
          if (pet.url.isNotEmpty) 'url': pet.url,
        });
        if (result['ok'] != true) return null;
        return decodeBotAvatarData('${result['dataUri']}');
      }),
    );

enum BotAvatarTab { bot, generate, upload, pet }

class BotAvatarPicker extends ConsumerStatefulWidget {
  const BotAvatarPicker({
    super.key,
    required this.bot,
    required this.shape,
    required this.color,
    required this.useImage,
    required this.enabled,
    required this.onShape,
    required this.onColor,
    required this.onImage,
    this.imageBytes,
    this.title = '',
    this.description = '',
  });

  final String bot;
  final String title;
  final String description;
  final String shape;
  final String color;
  final bool useImage;
  final bool enabled;
  final Uint8List? imageBytes;
  final ValueChanged<String> onShape;
  final ValueChanged<String> onColor;
  final ValueChanged<Uint8List?> onImage;

  @override
  ConsumerState<BotAvatarPicker> createState() => _BotAvatarPickerState();
}

class _BotAvatarPickerState extends ConsumerState<BotAvatarPicker> {
  final _prompt = TextEditingController();
  final _search = TextEditingController();
  final _picker = ImagePicker();
  BotAvatarTab _tab = BotAvatarTab.bot;
  bool? _imageAvailable;
  bool _probing = false;
  bool _generating = false;
  bool _loadingPets = false;
  String? _error;
  List<_PetChoice> _pets = const [];
  int _petLimit = 24;
  String? _selectedPet;

  @override
  void dispose() {
    _prompt.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _selectTab(BotAvatarTab tab) async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _tab = tab;
      _error = null;
    });
    if (tab == BotAvatarTab.generate) await _probeImageBackend();
    if (tab == BotAvatarTab.pet) await _loadPets();
  }

  Future<void> _probeImageBackend() async {
    if (_probing || _imageAvailable == true) return;
    final sync = ref.read(sessionSyncProvider);
    if (sync == null) return;
    setState(() => _probing = true);
    try {
      final result = await sync.gatewayRequest('image.generate', {
        'probe': true,
      });
      if (mounted) {
        setState(() => _imageAvailable = result['available'] == true);
      }
    } catch (_) {
      if (mounted) setState(() => _imageAvailable = false);
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _generate() async {
    if (_generating) return;
    final sync = ref.read(sessionSyncProvider);
    if (sync == null) return;
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final custom = _prompt.text.trim();
      final who = [
        widget.title.trim().isEmpty ? widget.bot : widget.title.trim(),
        widget.description.trim(),
      ].where((part) => part.isNotEmpty).join(' — ');
      final prompt = custom.isEmpty
          ? 'Cute minimal robot avatar for an AI agent named "$who". Friendly simple mascot face, bold flat vector style, solid color background, centered, no text.'
          : '$custom. Avatar for an AI agent: centered, bold flat vector style, solid color background, no text.';
      final result = await sync.gatewayRequest('image.generate', {
        'prompt': prompt,
        'aspect_ratio': 'square',
        'max_bytes': 8000000,
      });
      if (result['success'] != true) {
        throw StateError('${result['error'] ?? 'Avatar generation failed'}');
      }
      final bytes = await _resultImageBytes(result);
      widget.onImage(await normalizeBotAvatar(bytes));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<Uint8List> _resultImageBytes(Map<String, dynamic> result) async {
    final data = '${result['image_data'] ?? ''}';
    if (data.isNotEmpty) return decodeBotAvatarData(data);
    final url = Uri.tryParse('${result['image'] ?? ''}');
    if (url == null || !url.hasScheme) {
      throw StateError('The image backend did not return image data');
    }
    final response = await http.get(url).timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Could not download the generated image');
    }
    return response.bodyBytes;
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (file == null) return;
      final normalized = await normalizeBotAvatar(await file.readAsBytes());
      widget.onImage(normalized);
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not use that image: $error');
    }
  }

  Future<void> _loadPets() async {
    if (_loadingPets || _pets.isNotEmpty) return;
    final sync = ref.read(sessionSyncProvider);
    if (sync == null) return;
    setState(() {
      _loadingPets = true;
      _error = null;
    });
    try {
      final result = await sync.gatewayRequest('pet.gallery', const {});
      final raw = result['pets'];
      final pets = raw is List
          ? raw
                .whereType<Map>()
                .map(_PetChoice.fromJson)
                .where((pet) => pet.slug.isNotEmpty)
                .toList()
          : <_PetChoice>[];
      pets.sort((a, b) {
        final rank =
            (a.installed
                ? 0
                : a.curated
                ? 1
                : 2) -
            (b.installed
                ? 0
                : b.curated
                ? 1
                : 2);
        return rank != 0 ? rank : a.name.compareTo(b.name);
      });
      if (mounted) setState(() => _pets = pets);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load pets: $error');
    } finally {
      if (mounted) setState(() => _loadingPets = false);
    }
  }

  Future<void> _selectPet(_PetChoice pet) async {
    final sync = ref.read(sessionSyncProvider);
    if (sync == null) return;
    setState(() {
      _selectedPet = pet.slug;
      _error = null;
    });
    try {
      final thumb = await _petThumb(sync, pet);
      if (thumb == null) throw StateError('Could not load that pet');
      widget.onImage(await normalizeBotAvatar(thumb));
    } catch (error) {
      if (mounted) {
        setState(() {
          _selectedPet = null;
          _error = '$error';
        });
      }
    }
  }

  HermesBotProfile _shapePreview(String shape, String color) {
    return HermesBotProfile.fromJson({
      'name': widget.bot.isEmpty ? 'agent' : widget.bot,
      'ui_meta': {
        'hermes-bots': {
          'title': widget.title,
          'shape': shape,
          'color': color,
          'imageKind': 'shape',
        },
      },
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _search.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _pets
        : _pets
              .where(
                (pet) =>
                    pet.name.toLowerCase().contains(query) ||
                    pet.slug.toLowerCase().contains(query),
              )
              .toList();
    final visible = filtered.take(_petLimit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: _preview()),
        const SizedBox(height: 12),
        SegmentedButton<BotAvatarTab>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: BotAvatarTab.bot, label: Text('Bot')),
            ButtonSegment(
              value: BotAvatarTab.generate,
              label: Text('Generate'),
            ),
            ButtonSegment(value: BotAvatarTab.upload, label: Text('Upload')),
            ButtonSegment(value: BotAvatarTab.pet, label: Text('Pet')),
          ],
          selected: {_tab},
          onSelectionChanged: widget.enabled
              ? (selected) => unawaited(_selectTab(selected.single))
              : null,
        ),
        const SizedBox(height: 12),
        if (widget.useImage && _tab != BotAvatarTab.generate)
          Center(
            child: TextButton(
              onPressed: widget.enabled ? () => widget.onImage(null) : null,
              child: const Text('Remove image · use bot shape'),
            ),
          ),
        if (_tab == BotAvatarTab.bot) _botTab(theme),
        if (_tab == BotAvatarTab.generate) _generateTab(),
        if (_tab == BotAvatarTab.upload) _uploadTab(),
        if (_tab == BotAvatarTab.pet) _petTab(visible, filtered.length),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  Widget _preview() {
    if (widget.useImage && widget.imageBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.memory(
          widget.imageBytes!,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }
    if (widget.useImage) {
      return BotAvatar(
        bot: HermesBotProfile.fromJson({
          'name': widget.bot,
          'has_avatar': true,
          'ui_meta': {
            'hermes-bots': {
              'shape': widget.shape,
              'color': widget.color,
              'imageKind': 'photo',
            },
          },
        }),
        size: 72,
      );
    }
    return BotAvatar(bot: _shapePreview(widget.shape, widget.color), size: 72);
  }

  Widget _botTab(ThemeData theme) => Column(
    children: [
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final shape in botShapes)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: !widget.enabled
                  ? null
                  : () {
                      widget.onImage(null);
                      widget.onShape(shape);
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 52,
                height: 52,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: !widget.useImage && widget.shape == shape
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline.withValues(alpha: 0.3),
                    width: !widget.useImage && widget.shape == shape ? 2 : 1,
                  ),
                ),
                child: BotAvatar(
                  bot: _shapePreview(shape, widget.color),
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
              onTap: widget.enabled ? () => widget.onColor(color) : null,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(
                    int.parse(color.substring(1), radix: 16) | 0xFF000000,
                  ),
                  border: Border.all(
                    color: widget.color == color
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.outline.withValues(alpha: 0.35),
                    width: widget.color == color ? 3 : 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    ],
  );

  Widget _generateTab() {
    if (_probing) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_imageAvailable != true) {
      return Column(
        children: [
          const Text(
            'No image model is available on this gateway. Enable one in Hermes tools, then restart the gateway.',
            textAlign: TextAlign.center,
          ),
          TextButton(
            onPressed: widget.enabled ? _probeImageBackend : null,
            child: const Text('Check again'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _prompt,
          enabled: widget.enabled && !_generating,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Describe your avatar…',
            helperText: 'Leave blank to use the bot’s name and description.',
          ),
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: widget.enabled && !_generating ? _generate : null,
          icon: _generating
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
          label: Text(_generating ? 'Generating…' : 'Generate avatar'),
        ),
      ],
    );
  }

  Widget _uploadTab() => Wrap(
    alignment: WrapAlignment.center,
    spacing: 8,
    runSpacing: 8,
    children: [
      OutlinedButton.icon(
        onPressed: widget.enabled ? () => _pick(ImageSource.gallery) : null,
        icon: const Icon(Icons.photo_library_outlined),
        label: const Text('Photo library'),
      ),
      OutlinedButton.icon(
        onPressed: widget.enabled ? () => _pick(ImageSource.camera) : null,
        icon: const Icon(Icons.photo_camera_outlined),
        label: const Text('Camera'),
      ),
    ],
  );

  Widget _petTab(List<_PetChoice> visible, int filteredCount) {
    if (_loadingPets) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_pets.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'No pets are available in the gateway petdex.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Search ${_pets.length} pets…',
          ),
          onChanged: (_) => setState(() => _petLimit = 24),
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: visible.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 1.05,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemBuilder: (context, index) {
            final pet = visible[index];
            return _PetTile(
              pet: pet,
              selected: _selectedPet == pet.slug,
              enabled: widget.enabled,
              onTap: () => unawaited(_selectPet(pet)),
            );
          },
        ),
        if (visible.length < filteredCount)
          TextButton(
            onPressed: () => setState(
              () => _petLimit = math.min(_petLimit + 24, filteredCount),
            ),
            child: Text('Show more (${visible.length} of $filteredCount)'),
          ),
      ],
    );
  }
}

class _PetTile extends ConsumerStatefulWidget {
  const _PetTile({
    required this.pet,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final _PetChoice pet;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  ConsumerState<_PetTile> createState() => _PetTileState();
}

class _PetTileState extends ConsumerState<_PetTile> {
  Future<Uint8List?>? _thumb;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _thumb ??= _load();
  }

  Future<Uint8List?> _load() async {
    final sync = ref.read(sessionSyncProvider);
    if (sync == null) return null;
    try {
      return await _petThumb(sync, widget.pet);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: widget.enabled ? widget.onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.25),
            width: widget.selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: FutureBuilder<Uint8List?>(
                future: _thumb,
                builder: (context, snapshot) => snapshot.data == null
                    ? const Icon(Icons.pets_outlined)
                    : Image.memory(snapshot.data!, fit: BoxFit.contain),
              ),
            ),
            Text(
              widget.pet.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PetChoice {
  const _PetChoice({
    required this.slug,
    required this.name,
    required this.url,
    required this.installed,
    required this.curated,
  });

  factory _PetChoice.fromJson(Map item) => _PetChoice(
    slug: '${item['slug'] ?? ''}'.trim(),
    name: '${item['displayName'] ?? item['slug'] ?? ''}'.trim(),
    url: '${item['spritesheetUrl'] ?? ''}'.trim(),
    installed: item['installed'] == true,
    curated: item['curated'] == true,
  );

  final String slug;
  final String name;
  final String url;
  final bool installed;
  final bool curated;
}

Uint8List decodeBotAvatarData(String data) {
  final comma = data.indexOf(',');
  final payload = comma >= 0 ? data.substring(comma + 1) : data;
  if (payload.isEmpty) throw const FormatException('Image data is empty');
  return Uint8List.fromList(base64Decode(payload));
}

Future<Uint8List> normalizeBotAvatar(Uint8List bytes, {int edge = 256}) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final side = math.min(image.width, image.height).toDouble();
  final source = Rect.fromLTWH(
    (image.width - side) / 2,
    (image.height - side) / 2,
    side,
    side,
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    image,
    source,
    Rect.fromLTWH(0, 0, edge.toDouble(), edge.toDouble()),
    Paint()..filterQuality = FilterQuality.high,
  );
  final output = await recorder.endRecording().toImage(edge, edge);
  final data = await output.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) throw StateError('Could not encode the avatar');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
