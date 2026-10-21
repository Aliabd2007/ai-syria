import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/services/ai_proxy_service.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../data/models/chat_model.dart';

class ChatProvider extends ChangeNotifier {
  final _uuid = const Uuid();

  List<ChatModel> chats = [];
  List<MessageModel> messages = [];
  String? currentChatId;
  String selectedMode = 'fast';
  bool sending = false;
  String streamingText = '';
  String? error;

  bool get hasChats => chats.isNotEmpty;

  Future<void> loadChats() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final data = await Supabase.instance.client
          .from('chats')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      chats = (data as List).map((e) => ChatModel.fromJson(e as Map<String, dynamic>)).toList();
      await LocalStorageService.cacheChats(chats.map((c) => c.toJson()).toList());
    } catch (_) {
      // Offline fallback
      final cached = LocalStorageService.getCachedChats();
      chats = cached.map((e) => ChatModel.fromJson(Map<String, dynamic>.from(e))).toList();
    }
    notifyListeners();
  }

  Future<void> createChat({String? title}) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('createChat: no logged-in user');
      return;
    }
    final id = _uuid.v4();
    final chat = ChatModel(
      id: id,
      userId: userId,
      title: title ?? 'محادثة جديدة',
      mode: selectedMode,
      createdAt: DateTime.now(),
    );
    try {
      await Supabase.instance.client.from('chats').insert(chat.toJson());
    } catch (e) {
      debugPrint('createChat insert failed (RLS?): $e');
      // Still add locally so UI is not blocked; will sync on next load
    }
    chats.insert(0, chat);
    currentChatId = id;
    messages = [];
    notifyListeners();
  }

  Future<void> selectChat(String chatId) async {
    currentChatId = chatId;
    messages = [];
    notifyListeners();
    try {
      final data = await Supabase.instance.client
          .from('messages')
          .select()
          .eq('chat_id', chatId)
          .order('created_at', ascending: true);
      messages = (data as List).map((e) => MessageModel.fromJson(e as Map<String, dynamic>)).toList();
      await LocalStorageService.cacheMessages(chatId, messages.map((m) => m.toJson()).toList());
    } catch (_) {
      final cached = LocalStorageService.getCachedMessages(chatId);
      messages = cached.map((e) => MessageModel.fromJson(Map<String, dynamic>.from(e))).toList();
    }
    notifyListeners();
  }

  void setMode(String mode) {
    selectedMode = mode;
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || currentChatId == null || sending) return;
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final chatId = currentChatId!;

    // Optimistic user message
    final userMsg = MessageModel(
      id: _uuid.v4(),
      chatId: chatId,
      userId: userId,
      role: 'user',
      content: text,
      createdAt: DateTime.now(),
    );
    messages = [...messages, userMsg];
    sending = true;
    streamingText = '';
    error = null;
    notifyListeners();

    // Build history for API
    final history = messages.map((m) => <String, String>{'role': m.role, 'content': m.content}).toList();

    try {
      final buffer = StringBuffer();
      await for (final chunk in AiProxyService.streamChat(
        chatId: chatId,
        mode: selectedMode,
        messages: history,
      )) {
        buffer.write(chunk);
        streamingText = buffer.toString();
        notifyListeners();
      }
      final fullText = buffer.toString();
      final assistantMsg = MessageModel(
        id: _uuid.v4(),
        chatId: chatId,
        userId: userId,
        role: 'assistant',
        content: fullText.isEmpty ? '—' : fullText,
        createdAt: DateTime.now(),
      );
      messages = [...messages, assistantMsg];
      streamingText = '';
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  Future<void> deleteChat(String chatId) async {
    try {
      await Supabase.instance.client.from('chats').delete().eq('id', chatId);
    } catch (_) {}
    chats.removeWhere((c) => c.id == chatId);
    if (currentChatId == chatId) {
      currentChatId = null;
      messages = [];
    }
    notifyListeners();
  }
}
