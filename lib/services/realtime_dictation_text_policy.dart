import 'dart:math' as math;

class RealtimeRefinementDecision {
  final String text;
  final bool accepted;
  final String reason;

  const RealtimeRefinementDecision({
    required this.text,
    required this.accepted,
    required this.reason,
  });
}

class DictationSegmentMerge {
  final String text;
  final bool changed;
  final int droppedPrefixLength;
  final String reason;

  const DictationSegmentMerge({
    required this.text,
    required this.changed,
    required this.droppedPrefixLength,
    required this.reason,
  });
}

/// Keeps the stable streaming hypothesis unless a second-pass recognition is
/// demonstrably compatible with it.
RealtimeRefinementDecision chooseRealtimeRefinement({
  required String streamingText,
  required String refinedText,
}) {
  final streaming = streamingText.trim();
  final refined = refinedText.trim();
  if (refined.isEmpty) {
    return RealtimeRefinementDecision(
      text: streaming,
      accepted: false,
      reason: '精修结果为空',
    );
  }

  final refinedProfile = _TextProfile.from(refined);
  if (refinedProfile.recognizedUnits.isEmpty) {
    return RealtimeRefinementDecision(
      text: streaming,
      accepted: false,
      reason: '精修结果没有有效文字',
    );
  }
  if (refinedProfile.unknownRatio > 0.08) {
    return RealtimeRefinementDecision(
      text: streaming,
      accepted: false,
      reason: '精修结果包含过多异常符号',
    );
  }
  if (_hasExcessiveRepetition(refinedProfile.recognizedUnits)) {
    return RealtimeRefinementDecision(
      text: streaming,
      accepted: false,
      reason: '精修结果存在异常重复',
    );
  }
  if (streaming.isEmpty) {
    return RealtimeRefinementDecision(
      text: refined,
      accepted: true,
      reason: '流式结果为空，采用有效离线结果',
    );
  }

  final streamingProfile = _TextProfile.from(streaming);
  final sourceUnits = streamingProfile.recognizedUnits;
  final refinedUnits = refinedProfile.recognizedUnits;
  if (sourceUnits == refinedUnits) {
    return RealtimeRefinementDecision(
      text: refined,
      accepted: true,
      reason: '正文一致，仅规范格式',
    );
  }
  if (sourceUnits.length <= 3) {
    return RealtimeRefinementDecision(
      text: streaming,
      accepted: false,
      reason: '短文本差异过大',
    );
  }

  final lengthRatio = refinedUnits.length / sourceUnits.length;
  if (lengthRatio < 0.55 || lengthRatio > 1.55) {
    return RealtimeRefinementDecision(
      text: streaming,
      accepted: false,
      reason: '精修前后文字长度差异过大',
    );
  }
  if (streamingProfile.cjkRatio >= 0.35 &&
      refinedProfile.cjkRatio < streamingProfile.cjkRatio - 0.25) {
    return RealtimeRefinementDecision(
      text: streaming,
      accepted: false,
      reason: '精修结果发生异常语言漂移',
    );
  }
  if (streamingProfile.latinRatio >= 0.35 &&
      refinedProfile.latinRatio < streamingProfile.latinRatio - 0.3) {
    return RealtimeRefinementDecision(
      text: streaming,
      accepted: false,
      reason: '精修结果丢失过多英文内容',
    );
  }

  final similarity = _diceSimilarity(sourceUnits, refinedUnits);
  if (similarity < 0.52) {
    return RealtimeRefinementDecision(
      text: streaming,
      accepted: false,
      reason: '精修结果与流式文本相似度过低',
    );
  }
  return RealtimeRefinementDecision(
    text: refined,
    accepted: true,
    reason: '精修结果通过质量检查',
  );
}

/// Merges endpoint results without blindly appending repeated or overlapping
/// text returned around a stream reset.
DictationSegmentMerge mergeDictationSegment(
  String currentText,
  String nextSegment,
) {
  final current = currentText.trim();
  final segment = nextSegment.trim();
  if (segment.isEmpty) {
    return DictationSegmentMerge(
      text: current,
      changed: false,
      droppedPrefixLength: 0,
      reason: '空片段',
    );
  }
  if (current.isEmpty) {
    return DictationSegmentMerge(
      text: segment,
      changed: true,
      droppedPrefixLength: 0,
      reason: '首个片段',
    );
  }

  final currentUnits = _TextProfile.from(current).recognizedUnits;
  final segmentUnits = _TextProfile.from(segment).recognizedUnits;
  if (segmentUnits.isNotEmpty && currentUnits.endsWith(segmentUnits)) {
    return DictationSegmentMerge(
      text: current,
      changed: false,
      droppedPrefixLength: segment.length,
      reason: '忽略已提交的重复片段',
    );
  }
  if (currentUnits.length >= 4 && segmentUnits.startsWith(currentUnits)) {
    return DictationSegmentMerge(
      text: segment,
      changed: true,
      droppedPrefixLength: current.length,
      reason: '采用包含已有内容的累计结果',
    );
  }

  final boundaryCurrent = _stripTrailingBoundary(current).toLowerCase();
  final boundarySegment = _stripLeadingBoundary(segment);
  final comparableSegment = boundarySegment.toLowerCase();
  final maxOverlap = math.min(boundaryCurrent.length, comparableSegment.length);
  var overlap = 0;
  for (var length = maxOverlap; length >= 2; length--) {
    final candidate = comparableSegment.substring(0, length);
    final asciiOnly = candidate.codeUnits.every((unit) => unit < 128);
    if (asciiOnly && length < 4) continue;
    if (boundaryCurrent.endsWith(candidate)) {
      overlap = length;
      break;
    }
  }
  if (overlap > 0) {
    final remainder = boundarySegment.substring(overlap);
    return DictationSegmentMerge(
      text: '$current$remainder',
      changed: remainder.isNotEmpty,
      droppedPrefixLength: overlap,
      reason: '裁剪相邻片段重叠',
    );
  }

  final separator = RegExp(r'[。！？!?；;，,\n]$').hasMatch(current) ? '' : '。';
  return DictationSegmentMerge(
    text: '$current$separator$segment',
    changed: true,
    droppedPrefixLength: 0,
    reason: '追加独立片段',
  );
}

class _TextProfile {
  final String recognizedUnits;
  final double cjkRatio;
  final double latinRatio;
  final double unknownRatio;

  const _TextProfile({
    required this.recognizedUnits,
    required this.cjkRatio,
    required this.latinRatio,
    required this.unknownRatio,
  });

  factory _TextProfile.from(String value) {
    final recognized = StringBuffer();
    var cjk = 0;
    var latin = 0;
    var unknown = 0;
    var visible = 0;
    for (final rune in value.runes) {
      if (_isWhitespace(rune)) continue;
      visible++;
      if (_isCjk(rune) || _isKana(rune) || _isHangul(rune)) {
        recognized.writeCharCode(rune);
        cjk++;
      } else if (_isAsciiLetter(rune)) {
        recognized.writeCharCode(
          rune >= 0x41 && rune <= 0x5a ? rune + 0x20 : rune,
        );
        latin++;
      } else if (_isDigit(rune)) {
        recognized.writeCharCode(rune);
      } else if (!_isAllowedPunctuation(rune)) {
        unknown++;
      }
    }
    final scriptTotal = cjk + latin;
    return _TextProfile(
      recognizedUnits: recognized.toString(),
      cjkRatio: scriptTotal == 0 ? 0 : cjk / scriptTotal,
      latinRatio: scriptTotal == 0 ? 0 : latin / scriptTotal,
      unknownRatio: visible == 0 ? 0 : unknown / visible,
    );
  }
}

double _diceSimilarity(String left, String right) {
  if (left == right) return 1;
  if (left.isEmpty || right.isEmpty) return 0;
  if (left.length == 1 || right.length == 1) return 0;
  final counts = <String, int>{};
  for (var index = 0; index < left.length - 1; index++) {
    final pair = left.substring(index, index + 2);
    counts[pair] = (counts[pair] ?? 0) + 1;
  }
  var intersection = 0;
  for (var index = 0; index < right.length - 1; index++) {
    final pair = right.substring(index, index + 2);
    final count = counts[pair] ?? 0;
    if (count == 0) continue;
    intersection++;
    counts[pair] = count - 1;
  }
  return 2 * intersection / (left.length + right.length - 2);
}

bool _hasExcessiveRepetition(String value) {
  if (value.length < 8) return false;
  final maxUnit = math.min(40, value.length ~/ 3);
  for (var unitLength = 2; unitLength <= maxUnit; unitLength++) {
    for (var start = 0; start + unitLength * 3 <= value.length; start++) {
      final unit = value.substring(start, start + unitLength);
      var count = 1;
      var offset = start + unitLength;
      while (offset + unitLength <= value.length &&
          value.substring(offset, offset + unitLength) == unit) {
        count++;
        offset += unitLength;
      }
      if (count >= 3 && unitLength * count >= value.length * 0.45) return true;
    }
  }
  return false;
}

String _stripTrailingBoundary(String value) =>
    value.replaceFirst(RegExp(r'[\s。！？!?；;，,：:“”‘’、…—-]+$'), '');

String _stripLeadingBoundary(String value) =>
    value.replaceFirst(RegExp(r'^[\s。！？!?；;，,：:“”‘’、…—-]+'), '');

bool _isWhitespace(int rune) =>
    rune == 0x20 || rune == 0x09 || rune == 0x0a || rune == 0x0d;

bool _isAsciiLetter(int rune) =>
    (rune >= 0x41 && rune <= 0x5a) || (rune >= 0x61 && rune <= 0x7a);

bool _isDigit(int rune) =>
    (rune >= 0x30 && rune <= 0x39) || (rune >= 0xff10 && rune <= 0xff19);

bool _isCjk(int rune) =>
    (rune >= 0x3400 && rune <= 0x9fff) || (rune >= 0xf900 && rune <= 0xfaff);

bool _isKana(int rune) => rune >= 0x3040 && rune <= 0x30ff;

bool _isHangul(int rune) =>
    (rune >= 0x1100 && rune <= 0x11ff) || (rune >= 0xac00 && rune <= 0xd7af);

bool _isAllowedPunctuation(int rune) =>
    '.,!?;:\'"…—-()[]{}<>/\\@#%&+_=，。！？；：“”‘’、（）【】《》·'.runes.contains(rune);
