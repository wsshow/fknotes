import 'package:fknotes/models/local_chat.dart';
import 'package:fknotes/pages/local_chat_roles_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('role manager lists and highlights reusable roles', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 12);
    final existing = LocalChatPersona(
      id: 'english-coach',
      name: '英语教练',
      description: '练习日常口语',
      systemPrompt: '你是一位耐心的英语教练。',
      builtIn: false,
      createdAt: now,
      updatedAt: now,
    );
    final builtIn = LocalChatPersona(
      id: LocalChatPersona.defaultId,
      name: '通用助手',
      description: '准确、清晰地处理日常问题',
      systemPrompt: LocalChatPersona.defaultSystemPrompt,
      builtIn: true,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LocalChatRolesPage(
          selectedPersonaId: existing.id,
          initialPersonas: [builtIn, existing],
        ),
      ),
    );

    expect(find.text('角色管理'), findsOneWidget);
    expect(find.text('通用助手'), findsOneWidget);
    expect(find.text('英语教练'), findsOneWidget);
    expect(find.text('当前'), findsOneWidget);
    expect(find.byKey(const Key('local-chat-add-persona')), findsOneWidget);
  });
}
