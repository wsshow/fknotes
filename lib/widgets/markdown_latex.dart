import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import '../l10n/l10n.dart';

const markdownInlineMathTag = 'fk-math-inline';
const markdownBlockMathTag = 'fk-math-block';

/// GitHub Flavored Markdown extended with conservative LaTeX delimiters.
///
/// Parsing is kept here instead of using a broad delimiter extension so that
/// ordinary parentheses, square brackets and currency remain normal prose.
final md.ExtensionSet fkMarkdownExtensionSet = md.ExtensionSet(
  [const FkLatexBlockSyntax(), ...md.ExtensionSet.gitHubFlavored.blockSyntaxes],
  [
    FkDollarLatexInlineSyntax(),
    FkParenthesizedLatexInlineSyntax(),
    ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
  ],
);

/// Parses `$...$` without claiming escaped dollars or unfinished stream data.
class FkDollarLatexInlineSyntax extends md.InlineSyntax {
  FkDollarLatexInlineSyntax()
    : super(
        r'(?<!\\)\$(?!\$|\s)(?:(\d(?:\\[^\s]|[^\s\\\n$`])*?)|((?!\d)(?:\\.|[^\\\n$`])*?))(?<!\s)\$(?!\d)',
        startCharacter: 0x24,
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element.text(markdownInlineMathTag, match.group(1) ?? match.group(2)!),
    );
    return true;
  }
}

/// Parses the standard `\(...\)` inline-math form.
class FkParenthesizedLatexInlineSyntax extends md.InlineSyntax {
  FkParenthesizedLatexInlineSyntax()
    : super(r'\\\((?!\s)(.+?)(?<!\s)\\\)', startCharacter: 0x5c);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text(markdownInlineMathTag, match.group(1)!));
    return true;
  }
}

/// Parses standalone `$$...$$` and `\[...\]` display equations.
///
/// A block is recognized only after its closing delimiter is present. This is
/// important for token streaming: an unfinished equation remains visible as
/// plain text and never consumes the following Markdown document.
class FkLatexBlockSyntax extends md.BlockSyntax {
  const FkLatexBlockSyntax();

  @override
  RegExp get pattern => RegExp(r'^\s*(?:\$\$|\\\[)');

  @override
  bool canParse(md.BlockParser parser) {
    if (!super.canParse(parser)) return false;
    final opening = parser.current.content.trim();
    if (_sameLineContent(opening) != null) return true;
    final closing = switch (opening) {
      r'$$' => r'$$',
      r'\[' => r'\]',
      _ => null,
    };
    if (closing == null) return false;
    for (var offset = 1; parser.peek(offset) != null; offset++) {
      if (parser.peek(offset)!.content.trim() == closing) return true;
    }
    return false;
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final opening = parser.current.content.trim();
    final sameLine = _sameLineContent(opening);
    if (sameLine != null) {
      parser.advance();
      return md.Element.text(markdownBlockMathTag, sameLine);
    }

    final closing = opening == r'$$' ? r'$$' : r'\]';
    final lines = <String>[];
    parser.advance();
    while (!parser.isDone && parser.current.content.trim() != closing) {
      lines.add(parser.current.content);
      parser.advance();
    }
    if (!parser.isDone) parser.advance();
    return md.Element.text(markdownBlockMathTag, lines.join('\n').trim());
  }

  static String? _sameLineContent(String line) {
    if (line.startsWith(r'$$') && line.endsWith(r'$$') && line.length > 4) {
      return line.substring(2, line.length - 2).trim();
    }
    if (line.startsWith(r'\[') && line.endsWith(r'\]') && line.length > 4) {
      return line.substring(2, line.length - 2).trim();
    }
    return null;
  }
}

class FkLatexElementBuilder extends MarkdownElementBuilder {
  final bool displayMode;
  final TextStyle textStyle;

  FkLatexElementBuilder({required this.displayMode, required this.textStyle});

  @override
  bool isBlockElement() => displayMode;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final latex = element.textContent.trim();
    if (latex.isEmpty) return const SizedBox.shrink();

    final math = Math.tex(
      latex,
      mathStyle: displayMode ? MathStyle.display : MathStyle.text,
      textStyle: textStyle,
      onErrorFallback: (_) => Text(
        displayMode ? r'$$' + latex + r'$$' : r'$' + latex + r'$',
        style: textStyle.copyWith(fontFamily: 'monospace'),
      ),
    );
    if (!displayMode) {
      return Semantics(
        label: context.l10n.mathFormulaSemantics(latex),
        child: math,
      );
    }

    return Semantics(
      label: context.l10n.mathFormulaSemantics(latex),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: math,
        ),
      ),
    );
  }
}
