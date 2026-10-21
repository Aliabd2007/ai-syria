import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_math_fork/flutter_math.dart';

class MessageBubble extends StatelessWidget {
  final String role;
  final String content;
  final bool isStreaming;

  const MessageBubble({
    super.key,
    required this.role,
    required this.content,
    this.isStreaming = false,
  });

  bool get isUser => role == 'user';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isUser
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isUser ? const Radius.circular(4) : null,
            bottomLeft: !isUser ? const Radius.circular(4) : null,
          ),
        ),
        child: isUser
            ? SelectableText(content, style: Theme.of(context).textTheme.bodyMedium)
            : _MarkdownWithExtras(content: content, isDark: isDark, isStreaming: isStreaming),
      ),
    );
  }
}

class _MarkdownWithExtras extends StatelessWidget {
  final String content;
  final bool isDark;
  final bool isStreaming;

  const _MarkdownWithExtras({required this.content, required this.isDark, required this.isStreaming});

  @override
  Widget build(BuildContext context) {
    // Split LaTeX blocks: $$...$$ and $...$ and ```code blocks handled by markdown
    // For simplicity, render markdown and handle inline LaTeX via custom builder
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MarkdownBody(
          data: content + (isStreaming ? ' ▌' : ''),
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            p: Theme.of(context).textTheme.bodyMedium,
            code: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              backgroundColor: isDark ? Colors.grey[850] : Colors.grey[100],
            ),
            codeblockDecoration: BoxDecoration(
              color: isDark ? const Color(0xFF282C34) : const Color(0xFFF6F8FA),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          builders: {
            'code': CodeBlockBuilder(isDark: isDark),
          },
          onTapLink: (text, href, title) {},
        ),
        // Inline LaTeX: detect $...$ outside code blocks
        ..._buildLatexWidgets(context),
      ],
    );
  }

  List<Widget> _buildLatexWidgets(BuildContext context) {
    // Extract display math $$...$$
    final displayRegex = RegExp(r'\$\$(.+?)\$\$', dotAll: true);
    final widgets = <Widget>[];
    for (final m in displayRegex.allMatches(content)) {
      final latex = m.group(1)!.trim();
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Math.tex(latex, textStyle: Theme.of(context).textTheme.bodyLarge),
          ),
        ),
      );
    }
    return widgets;
  }
}

class CodeBlockBuilder extends MarkdownElementBuilder {
  final bool isDark;
  CodeBlockBuilder({required this.isDark});

  @override
  @override
  Widget? visitElementAfter(
    md.Element element,
    TextStyle? preferredStyle,
  ) {
    final code = element.textContent;
    final lang = element.attributes['class']?.replaceFirst('language-', '') ?? 'plaintext';

    return Stack(
      children: [
        HighlightView(
          code,
          language: lang,
          theme: isDark ? atomOneDarkTheme : githubTheme,
          padding: const EdgeInsets.all(12),
          textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
        Positioned(
          top: 4,
          left: 4,
          child: Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.copy, size: 16),
              tooltip: 'نسخ',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('تم النسخ')));
              },
            ),
          ),
        ),
      ],
    );
  }
}
