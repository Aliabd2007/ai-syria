import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/app_constants.dart';

class AiProxyService {
  /// Sends a streaming chat request to the Edge Function.
  /// Yields text chunks as they arrive (SSE).
  static Stream<String> streamChat({
    required String chatId,
    required String mode,
    required List<Map<String, String>> messages,
  }) async* {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) throw Exception('غير مسجل الدخول');

    final request = http.Request(
      'POST',
      Uri.parse(AppConstants.aiProxyUrl),
    );
    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'apikey': AppConstants.supabaseAnonKey,
    });
    request.body = jsonEncode({
      'chat_id': chatId,
      'mode': mode,
      'messages': messages,
    });

    final streamed = await request.send();

    if (streamed.statusCode == 429) {
      throw Exception('تم تجاوز الحد اليومي — حاول غداً');
    }
    if (streamed.statusCode == 403) {
      throw Exception('انتهى اشتراكك — جدد الاشتراك للمتابعة');
    }
    if (streamed.statusCode == 401) {
      throw Exception('انتهت الجلسة — سجل دخول مجدداً');
    }
    if (streamed.statusCode != 200) {
      final body = await streamed.stream.bytesToString();
      throw Exception('خطأ ${streamed.statusCode}: $body');
    }

    // Parse SSE stream — yield chunks as they arrive
    yield* streamed.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asyncMap((line) {
          final trimmed = line.trim();
          if (!trimmed.startsWith('data:')) return null;
          final payload = trimmed.substring(5).trim();
          if (payload == '[DONE]') return null;
          try {
            final j = jsonDecode(payload) as Map<String, dynamic>;
            final delta = j['choices']?[0]?['delta']?['content'] as String?;
            return delta;
          } catch (_) {
            return null;
          }
        })
        .where((e) => e != null)
        .cast<String>();
  }

  /// Non-streaming fallback: collects full response.
  static Future<String> chat({
    required String chatId,
    required String mode,
    required List<Map<String, String>> messages,
  }) async {
    final buffer = StringBuffer();
    await for (final chunk in streamChat(chatId: chatId, mode: mode, messages: messages)) {
      buffer.write(chunk);
    }
    return buffer.toString();
  }
}
