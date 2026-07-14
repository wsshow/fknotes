class LocalChatCitationFormatter {
  static final _citationMarker = RegExp(r'\[N\d+\]');
  static final _citationOnlyLine = RegExp(
    r'^[ \t]*(?:\[N\d+\][ \t]*(?:[,，、;；][ \t]*)?)+[.!。]?[ \t]*$',
    multiLine: true,
  );
  static final _blankLine = RegExp(r'^[ \t]+$', multiLine: true);

  static String normalize(String content, {required int sourceCount}) {
    if (sourceCount <= 0 || content.isEmpty) return content;
    var normalized = sourceCount == 1
        ? content.replaceAll(_citationMarker, '')
        : content.replaceAll(_citationOnlyLine, '');
    normalized = normalized.replaceAll(
      RegExp(r'[ \t]+([,，。.!?！？;；:：])'),
      r'$1',
    );
    normalized = normalized.replaceAll(_blankLine, '');
    normalized = normalized.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return normalized.trim();
  }
}
