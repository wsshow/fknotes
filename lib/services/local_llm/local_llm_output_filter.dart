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
    return visible
        .replaceAll(RegExp(r'</think>', caseSensitive: false), '')
        .trimLeft();
  }
}
