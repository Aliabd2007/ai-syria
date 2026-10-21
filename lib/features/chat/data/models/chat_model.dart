class ChatModel {
  final String id;
  final String userId;
  final String title;
  final String mode;
  final DateTime createdAt;

  ChatModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.mode,
    required this.createdAt,
  });

  factory ChatModel.fromJson(Map<String, dynamic> j) => ChatModel(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        title: j['title'] as String? ?? 'محادثة جديدة',
        mode: j['mode'] as String? ?? 'fast',
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'title': title,
        'mode': mode,
        'created_at': createdAt.toIso8601String(),
      };
}

class MessageModel {
  final String id;
  final String chatId;
  final String userId;
  final String role; // user | assistant | system
  final String content;
  final int? tokens;
  final DateTime createdAt;

  MessageModel({
    required this.id,
    required this.chatId,
    required this.userId,
    required this.role,
    required this.content,
    this.tokens,
    required this.createdAt,
  });

  factory MessageModel.fromJson(Map<String, dynamic> j) => MessageModel(
        id: j['id'] as String,
        chatId: j['chat_id'] as String,
        userId: j['user_id'] as String,
        role: j['role'] as String,
        content: j['content'] as String,
        tokens: j['tokens'] as int?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'chat_id': chatId,
        'user_id': userId,
        'role': role,
        'content': content,
        'tokens': tokens,
        'created_at': createdAt.toIso8601String(),
      };
}
