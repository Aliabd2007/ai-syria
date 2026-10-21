import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/services/theme_service.dart';
import '../providers/chat_provider.dart';
import '../widgets/message_bubble.dart';
import '../widgets/mode_bar.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadChats();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await context.read<ChatProvider>().sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Consumer<ChatProvider>(
        builder: (context, chat, _) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('AI سوريا'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.brightness_6),
                  onPressed: () => context.read<ThemeService>().toggle(),
                  tooltip: 'المظهر',
                ),
                IconButton(icon: const Icon(Icons.account_balance_wallet), onPressed: () => Navigator.pushNamed(context, '/subscription'), tooltip: 'الاشتراك'),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'logout') Navigator.pushReplacementNamed(context, '/login');
                    if (v == 'new_chat') chat.createChat();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'new_chat', child: Text('محادثة جديدة')),
                    PopupMenuItem(value: 'logout', child: Text('تسجيل الخروج')),
                  ],
                ),
              ],
            ),
            drawer: _ChatDrawer(chats: chat.chats, currentId: chat.currentChatId),
            body: Column(
              children: [
                ModeBar(selected: chat.selectedMode, onSelect: chat.setMode),
                const Divider(height: 1),
                Expanded(
                  child: chat.currentChatId == null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              const Text('ابدأ محادثة جديدة'),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: () => chat.createChat(),
                                icon: const Icon(Icons.add),
                                label: const Text('محادثة جديدة'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: chat.messages.length + (chat.sending ? 1 : 0) + (chat.error != null ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (chat.error != null && i == chat.messages.length + (chat.sending ? 1 : 0)) {
                              return Container(
                                margin: const EdgeInsets.all(12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8)),
                                child: Text(chat.error!, style: const TextStyle(color: Colors.red)),
                              );
                            }
                            if (chat.sending && i == chat.messages.length) {
                              return MessageBubble(role: 'assistant', content: chat.streamingText, isStreaming: true);
                            }
                            final m = chat.messages[i];
                            return MessageBubble(role: m.role, content: m.content);
                          },
                        ),
                ),
                if (chat.currentChatId != null) _InputBar(controller: _input, onSend: _send, sending: chat.sending),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ChatDrawer extends StatelessWidget {
  final List chats;
  final String? currentId;
  const _ChatDrawer({required this.chats, required this.currentId});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer),
            child: const Center(child: Text('المحادثات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ),
          Expanded(
            child: chats.isEmpty
                ? const Center(child: Text('لا توجد محادثات'))
                : ListView.builder(
                    itemCount: chats.length,
                    itemBuilder: (_, i) {
                      final c = chats[i] as dynamic;
                      return ListTile(
                        title: Text(c.title as String),
                        subtitle: Text(c.mode as String),
                        selected: c.id == currentId,
                        onTap: () {
                          Navigator.pop(context);
                          context.read<ChatProvider>().selectChat(c.id as String);
                        },
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => context.read<ChatProvider>().deleteChat(c.id as String),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                context.read<ChatProvider>().createChat();
              },
              icon: const Icon(Icons.add),
              label: const Text('محادثة جديدة'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool sending;
  const _InputBar({required this.controller, required this.onSend, required this.sending});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                decoration: const InputDecoration(hintText: 'اكتب رسالتك...', border: OutlineInputBorder(), isDense: true),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
