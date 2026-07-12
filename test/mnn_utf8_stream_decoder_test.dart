import 'dart:convert';

import 'package:fknotes/services/local_llm/mnn_native_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reassembles Chinese and emoji split across native callbacks', () {
    final bytes = utf8.encode('中文🙂，完整输出');
    final decoder = MnnUtf8StreamDecoder();
    final output = StringBuffer();

    for (final byte in bytes) {
      output.write(decoder.add([byte]));
    }
    output.write(decoder.close());

    expect(output.toString(), '中文🙂，完整输出');
    expect(output.toString(), isNot(contains('�')));
  });

  test('retains an incomplete suffix until the remaining bytes arrive', () {
    final bytes = utf8.encode('测');
    final decoder = MnnUtf8StreamDecoder();

    expect(decoder.add(bytes.take(2).toList()), isEmpty);
    expect(decoder.add(bytes.skip(2).toList()), '测');
    expect(decoder.close(), isEmpty);
  });

  test('rejects a stream that ends inside a UTF-8 character', () {
    final bytes = utf8.encode('试');
    final decoder = MnnUtf8StreamDecoder();
    decoder.add(bytes.take(1).toList());

    expect(decoder.close, throwsFormatException);
  });
}
