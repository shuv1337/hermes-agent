import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:hermes_mobile/core/network/gateway_auth.dart';
import 'package:hermes_mobile/l10n/l10n.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

/// Renders assistant/user message body with GFM-style markdown.
///
/// Code fences get a dark monospace block + copy button; inline `code` is
/// pill-styled. Links open via [MarkdownStyleSheet] defaults + [onTapLink].
///
/// Images never fetch on paint — see [markdownImageDisposition] and
/// [_MarkdownImage]. Message bodies are written by an LLM and routinely
/// contain text it pulled off the open web, so they are treated as
/// attacker-influenced.
class MessageMarkdown extends StatefulWidget {
  const MessageMarkdown({
    super.key,
    required this.data,
    this.color,
    this.selectable = true,
  });

  final String data;
  final Color? color;
  final bool selectable;

  @override
  State<MessageMarkdown> createState() => _MessageMarkdownState();
}

class _MessageMarkdownState extends State<MessageMarkdown> {
  /// Which remote images the user has explicitly asked to load, for this
  /// widget only. Held in the [State] rather than in the widget so it
  /// survives the per-token rebuild storm of a streaming message, and dies
  /// with the widget — it is never written to disk, so a granted load is not
  /// carried across app launches.
  final _ImageConsent _consent = _ImageConsent();

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final selectable = widget.selectable;
    final theme = Theme.of(context);
    final fg = widget.color ?? theme.colorScheme.onSurface;
    // NOTE: keyed off the *actual* rendered surface color, not
    // `theme.brightness`. Several built-in skins (midnight/ember/mono/
    // cyberpunk/slate — see hermes_skins.dart) have no `darkColors` and
    // reuse the same dark-looking palette for both the light- and
    // dark-theme slots, so `theme.brightness` can read Brightness.light
    // while the page is actually dark. That mismatch made code blocks
    // render a light card with light (onSurface) text on top of it —
    // unreadable. `estimateBrightnessForColor` reflects what's really on
    // screen, matching `HermesSkin.prefersDark`'s approach.
    final surfaceIsDark =
        ThemeData.estimateBrightnessForColor(theme.scaffoldBackgroundColor) ==
        Brightness.dark;
    final codeBg = surfaceIsDark
        ? const Color(0xFF12151A)
        : const Color(0xFFF0F2F5);
    final codeBorder = theme.colorScheme.outline.withValues(alpha: 0.35);
    final inlineCodeBg = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.85,
    );

    final base =
        theme.textTheme.bodyLarge?.copyWith(color: fg, height: 1.45) ??
        TextStyle(color: fg, fontSize: 16, height: 1.45);

    final sheet = MarkdownStyleSheet(
      p: base,
      pPadding: const EdgeInsets.only(bottom: 8),
      h1: base.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      h2: base.copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      h3: base.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      h4: base.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      h1Padding: const EdgeInsets.only(top: 12, bottom: 6),
      h2Padding: const EdgeInsets.only(top: 10, bottom: 4),
      h3Padding: const EdgeInsets.only(top: 8, bottom: 4),
      strong: base.copyWith(fontWeight: FontWeight.w700),
      em: base.copyWith(fontStyle: FontStyle.italic),
      del: base.copyWith(decoration: TextDecoration.lineThrough),
      listBullet: base,
      listIndent: 22,
      blockSpacing: 10,
      blockquote: base.copyWith(
        color: fg.withValues(alpha: 0.75),
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.55),
            width: 3,
          ),
        ),
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      code: base.copyWith(
        fontFamily: 'monospace',
        fontSize: (base.fontSize ?? 16) * 0.9,
        backgroundColor: inlineCodeBg,
        color: theme.colorScheme.secondary,
      ),
      codeblockPadding: EdgeInsets.zero,
      codeblockDecoration: const BoxDecoration(), // handled by custom builder
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: codeBorder, width: 1)),
      ),
      a: base.copyWith(
        color: theme.colorScheme.secondary,
        decoration: TextDecoration.underline,
        decorationColor: theme.colorScheme.secondary.withValues(alpha: 0.5),
      ),
      tableHead: base.copyWith(fontWeight: FontWeight.w700),
      tableBody: base.copyWith(fontSize: (base.fontSize ?? 16) * 0.92),
      tableBorder: TableBorder.all(color: codeBorder, width: 0.5),
      tableHeadAlign: TextAlign.left,
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      checkbox: base,
    );

    final body = MarkdownBody(
      data: data,
      selectable: selectable,
      styleSheet: sheet,
      softLineBreak: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      builders: {
        'code': _CodeElementBuilder(
          codeBg: codeBg,
          codeBorder: codeBorder,
          fg: fg,
          monoSize: (base.fontSize ?? 16) * 0.88,
        ),
      },
      // Without this, `flutter_markdown_plus` falls back to
      // `kDefaultImageBuilder`, which resolves http(s) with `Image.network`
      // and *everything else* — `file:`, bare relative paths, unknown
      // schemes — with `Image.file`. That makes
      // `![](https://attacker.example/p.png)` in an agent-written message a
      // zero-click beacon: the GET fires the moment the bubble paints,
      // confirming the message was opened and leaking the device's public IP
      // and User-Agent, and it can be aimed at the user's own LAN. Every
      // image goes through the gate instead.
      imageBuilder: (uri, title, alt) => _MarkdownImage(
        uri: uri,
        alt: alt,
        consent: _consent,
        fg: fg,
        labelStyle:
            theme.textTheme.bodySmall?.copyWith(
              color: fg.withValues(alpha: 0.75),
            ) ??
            TextStyle(color: fg.withValues(alpha: 0.75), fontSize: 12),
        borderColor: codeBorder,
      ),
      onTapLink: (text, href, title) async {
        final uri = href == null ? null : Uri.tryParse(href);
        final safe =
            uri != null &&
            uri.hasScheme &&
            const {
              'http',
              'https',
              'mailto',
            }.contains(uri.scheme.toLowerCase());
        if (safe) {
          try {
            if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
              return;
            }
          } catch (_) {
            // Copy fallback below keeps the link usable on restricted devices.
          }
        }
        if (href != null && href.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: href));
          if (!context.mounted) return;
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(context.l10n.copiedLink(href)),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
    );

    return body;
  }
}

/// What the renderer is allowed to do with a Markdown image source.
///
/// The rule is "no byte leaves the device because a message painted". A
/// `data:` URI carries its own bytes, so it is the only source that renders
/// straight away; everything else is inert until the user says otherwise,
/// and some of it stays inert no matter what.
enum MarkdownImageDisposition {
  /// A self-contained `data:` image. Decoded from the URI itself — no
  /// socket is opened — so it renders exactly as it did before the gate.
  inline,

  /// A public `http(s)` source. Never fetched on paint: the user gets an
  /// inert placeholder naming the host and has to tap it before the request
  /// happens.
  askFirst,

  /// An `http(s)` source pointed at loopback, RFC1918 LAN, link-local,
  /// CGNAT/tailnet, mDNS `.local` or MagicDNS `.ts.net` space.
  ///
  /// DELIBERATELY NOT OFFERED, not even behind a tap. This is the
  /// SSRF-flavoured case: `![](http://192.168.1.1/admin?reboot=1)` asks the
  /// phone — which sits on the user's private network by design, because
  /// that is where the gateway lives — to issue a request the user has no
  /// way to evaluate. "Do you want to load an image from 192.168.1.1?" is
  /// not a question anyone can answer correctly; the host name carries no
  /// signal about what the request would *do*, unlike a public host where
  /// "that's attacker.example" is a judgement a person can actually make.
  /// A gateway-served image reaches the app through the authenticated
  /// artifact pipeline instead, so nothing legitimate depends on this.
  blockedPrivate,

  /// Anything else — `file:`, bare relative paths, protocol-relative `//`,
  /// `resource:`, unknown schemes, and non-image `data:` payloads. Inert,
  /// and never handed to `Image.file` or a network fetch.
  blocked,
}

/// Classifies an image source. Pure, so the rules are unit-testable without
/// pumping a widget.
MarkdownImageDisposition markdownImageDisposition(Uri uri) {
  switch (uri.scheme) {
    // `Uri` lower-cases the scheme during parsing, so `DATA:`/`HTTPS:` land
    // here too.
    case 'data':
      final data = uri.data;
      if (data == null) return MarkdownImageDisposition.blocked;
      return data.mimeType.toLowerCase().startsWith('image/')
          ? MarkdownImageDisposition.inline
          : MarkdownImageDisposition.blocked;
    case 'http':
    case 'https':
      if (uri.host.isEmpty) return MarkdownImageDisposition.blocked;
      return GatewayAuthClient.isPrivateOrLoopbackHost(uri.host)
          ? MarkdownImageDisposition.blockedPrivate
          : MarkdownImageDisposition.askFirst;
    default:
      return MarkdownImageDisposition.blocked;
  }
}

/// Per-view record of the remote images the user chose to load.
///
/// Scoped to one [MessageMarkdown] state: shared by every image in that
/// message so a rebuild (or a re-parse triggered by the next streamed token)
/// finds the grant still there, and gone as soon as the widget is.
class _ImageConsent {
  final Set<String> _granted = <String>{};

  bool has(Uri uri) => _granted.contains(uri.toString());

  void grant(Uri uri) => _granted.add(uri.toString());
}

/// Decoded `data:` image payloads, keyed by the URI text.
///
/// `MemoryImage` keys Flutter's image cache on the *identity* of the byte
/// list, so handing `Image.memory` a freshly-decoded `Uint8List` on every
/// rebuild would re-decode the picture on every streamed token. Reusing one
/// instance keeps the cache hitting. Bounded, so a long transcript cannot
/// grow it without limit; a miss only costs one base64 decode.
final Map<String, Uint8List> _dataImageBytes = <String, Uint8List>{};
const int _dataImageBytesLimit = 24;

Uint8List? _decodeDataImage(Uri uri) {
  final key = uri.toString();
  final cached = _dataImageBytes[key];
  if (cached != null) return cached;
  final data = uri.data;
  if (data == null) return null;
  final Uint8List bytes;
  try {
    bytes = data.contentAsBytes();
  } catch (_) {
    return null; // Malformed payload — treated as an unusable source.
  }
  if (_dataImageBytes.length >= _dataImageBytesLimit) {
    _dataImageBytes.remove(_dataImageBytes.keys.first);
  }
  _dataImageBytes[key] = bytes;
  return bytes;
}

/// The image gate. Renders inline, inert-with-a-tap, or inert-full-stop
/// according to [markdownImageDisposition].
class _MarkdownImage extends StatefulWidget {
  const _MarkdownImage({
    required this.uri,
    required this.alt,
    required this.consent,
    required this.fg,
    required this.labelStyle,
    required this.borderColor,
  });

  final Uri uri;
  final String? alt;
  final _ImageConsent consent;
  final Color fg;
  final TextStyle labelStyle;
  final Color borderColor;

  @override
  State<_MarkdownImage> createState() => _MarkdownImageState();
}

class _MarkdownImageState extends State<_MarkdownImage> {
  // Classified once per source rather than per build: a streaming message
  // rebuilds on every token and the IPv4/host parsing is not free.
  late MarkdownImageDisposition _disposition = markdownImageDisposition(
    widget.uri,
  );

  @override
  void didUpdateWidget(covariant _MarkdownImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri) {
      _disposition = markdownImageDisposition(widget.uri);
    }
  }

  /// Long hosts are trimmed so the label can't push a chat bubble wide, but
  /// the *start* is kept — that is the part a user reads to spot
  /// `attacker.example`.
  String get _host {
    final host = widget.uri.host;
    return host.length <= 48 ? host : '${host.substring(0, 47)}…';
  }

  void _load() {
    widget.consent.grant(widget.uri);
    // The grant lives in the shared consent object, so this setState only
    // has to repaint; the next re-parse of the streamed message will read it
    // back and keep the image loaded.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    switch (_disposition) {
      case MarkdownImageDisposition.inline:
        final bytes = _decodeDataImage(widget.uri);
        if (bytes == null) {
          return _placeholder(
            icon: Icons.image_not_supported_outlined,
            label: l10n.imageBlockedSource,
          );
        }
        return Image.memory(
          bytes,
          errorBuilder: (context, error, stackTrace) => _placeholder(
            icon: Icons.broken_image_outlined,
            label: l10n.imageLoadFailed,
          ),
        );
      case MarkdownImageDisposition.askFirst:
        if (!widget.consent.has(widget.uri)) {
          return _placeholder(
            icon: Icons.download_outlined,
            label: l10n.imageTapToLoad(_host),
            onTap: _load,
          );
        }
        return Image.network(
          widget.uri.toString(),
          errorBuilder: (context, error, stackTrace) => _placeholder(
            icon: Icons.broken_image_outlined,
            label: l10n.imageLoadFailed,
          ),
        );
      case MarkdownImageDisposition.blockedPrivate:
        return _placeholder(
          icon: Icons.lock_outline,
          label: l10n.imageBlockedPrivateNetwork(_host),
        );
      case MarkdownImageDisposition.blocked:
        return _placeholder(
          icon: Icons.image_not_supported_outlined,
          label: l10n.imageBlockedSource,
        );
    }
  }

  Widget _placeholder({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    // `Wrap`, not `Row`: the markdown builder drops inline children into a
    // `Wrap`, which hands them unbounded width — a `Flexible`/`Expanded`
    // child would assert there.
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: widget.borderColor),
        color: widget.borderColor.withValues(alpha: 0.12),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 7,
        children: [
          Icon(icon, size: 15, color: widget.fg.withValues(alpha: 0.7)),
          Text(label, style: widget.labelStyle),
        ],
      ),
    );
    final described = Semantics(
      label: widget.alt == null || widget.alt!.isEmpty
          ? label
          : '${widget.alt}. $label',
      button: onTap != null,
      child: content,
    );
    if (onTap == null) return described;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: described,
    );
  }
}

/// Custom fenced + indented code rendering with copy affordance.
class _CodeElementBuilder extends MarkdownElementBuilder {
  _CodeElementBuilder({
    required this.codeBg,
    required this.codeBorder,
    required this.fg,
    required this.monoSize,
  });

  final Color codeBg;
  final Color codeBorder;
  final Color fg;
  final double monoSize;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // Fenced blocks carry class="language-foo"; multi-line without class
    // is treated as a block too. Single-line bare `code` stays inline.
    final classes = element.attributes['class'] ?? '';
    final text = element.textContent;
    final isBlock = classes.isNotEmpty || text.contains('\n');

    if (!isBlock) {
      // Inline: pill monospace (styleSheet.code alone is easy to miss).
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: codeBorder.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: monoSize,
            color: fg.withValues(alpha: 0.92),
            height: 1.25,
          ),
        ),
      );
    }

    var language = '';
    if (classes.startsWith('language-')) {
      language = classes.substring('language-'.length);
    }

    var code = text;
    if (code.endsWith('\n')) {
      code = code.substring(0, code.length - 1);
    }

    return _CodeBlock(
      code: code,
      language: language,
      codeBg: codeBg,
      codeBorder: codeBorder,
      fg: fg,
      monoSize: monoSize,
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({
    required this.code,
    required this.language,
    required this.codeBg,
    required this.codeBorder,
    required this.fg,
    required this.monoSize,
  });

  final String code;
  final String language;
  final Color codeBg;
  final Color codeBorder;
  final Color fg;
  final double monoSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: codeBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: codeBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: language + copy
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      language.isEmpty ? 'code' : language,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: fg.withValues(alpha: 0.5),
                        fontFamily: 'monospace',
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.copy,
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        SnackBar(
                          content: Text(context.l10n.codeCopied),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    icon: Icon(
                      Icons.copy_rounded,
                      color: fg.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Scrollable wide code
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: SelectableText(
                code,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: monoSize,
                  height: 1.4,
                  color: fg.withValues(alpha: 0.92),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
