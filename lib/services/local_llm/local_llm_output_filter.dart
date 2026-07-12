/// Removes model-internal reasoning tags before text reaches the UI or storage.
class LocalLlmOutputFilter {
  static String visibleText(String value) {
    var visible = value.replaceAll(
      RegExp(r'<think>.*?</think>', dotAll: true, caseSensitive: false),
      '',
    );
    final openReasoning = RegExp(
      r'<think>',
      caseSensitive: false,
    ).firstMatch(visible);
    if (openReasoning != null) {
      visible = visible.substring(0, openReasoning.start);
    }
    visible = visible.replaceAll(RegExp(r'</think>', caseSensitive: false), '');
    visible = visible.replaceAll(
      RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'),
      '',
    );
    return _removeStandaloneLayoutTags(
      visible,
    ).replaceFirst(RegExp(r'^(?:[ \t]*\r?\n)+'), '');
  }

  static String _removeStandaloneLayoutTags(String value) {
    final output = <String>[];
    var insideCodeFence = false;
    final fence = RegExp(r'^\s*(?:```|~~~)');
    final layoutTag = RegExp(
      r'^\s*</?(?:div|section|article|main)>\s*$',
      caseSensitive: false,
    );
    for (final line in value.split('\n')) {
      if (fence.hasMatch(line)) {
        insideCodeFence = !insideCodeFence;
        output.add(line);
        continue;
      }
      if (!insideCodeFence && layoutTag.hasMatch(line)) continue;
      output.add(line);
    }
    return output.join('\n');
  }
}
