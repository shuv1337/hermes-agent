import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:hermes_mobile/l10n/l10n.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

/// Renders assistant/user message body with GFM-style markdown.
///
/// Code fences get a dark monospace block + copy button; inline `code` is
/// pill-styled. Links open via [MarkdownStyleSheet] defaults + [onTapLink].
class MessageMarkdown extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = color ?? theme.colorScheme.onSurface;
    final codeBg = theme.brightness == Brightness.dark
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
