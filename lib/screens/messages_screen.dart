import 'package:flutter/material.dart';
import '../theme.dart';
import '../controller.dart';
import '../data.dart';
import '../widgets.dart';
import 'relationships_screen.dart';

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        const ScreenHead('Messages'),
        for (final contact in kContacts) ...[
          _ConversationRow(contact: contact),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 10),
        TLabel('Personal', color: c.inkFaint),
        const SizedBox(height: 9),
        for (final p in kPersonalContacts) ...[
          PersonalConversationRow(contact: p),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ConversationRow extends StatelessWidget {
  final Contact contact;
  const _ConversationRow({required this.contact});

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final thread = g.threads[contact.id]!;
    final last = thread.isNotEmpty ? thread.last : null;
    final hasUnread = g.unread && last != null && !last.fromMe;

    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () {
        if (hasUnread) g.markMessagesRead();
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadScreen(contactId: contact.id)));
      },
      child: Row(children: [
        ContactAvatar(contact.initials),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(contact.name, style: AppText.sans(size: 14, weight: FontWeight.w600, color: c.ink)),
              const SizedBox(width: 7),
              Text(contact.role, style: AppText.sans(size: 10.5, weight: FontWeight.w500, color: c.inkFaint)),
            ]),
            const SizedBox(height: 4),
            Text(
              last?.text ?? 'No messages yet.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.sans(size: 12.5, weight: FontWeight.w500, color: c.inkSoft),
            ),
          ]),
        ),
        if (hasUnread)
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.neg),
          ),
      ]),
    );
  }
}

class ChatThreadScreen extends StatelessWidget {
  final String contactId;
  const ChatThreadScreen({super.key, required this.contactId});

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final contact = kContact[contactId]!;

    return Scaffold(
      backgroundColor: c.appBg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
            child: Row(children: [
              IconButton(icon: Icon(Icons.arrow_back, color: c.ink, size: 20), onPressed: () => Navigator.of(context).pop()),
              ContactAvatar(contact.initials, size: 32),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(contact.name, style: AppText.sans(size: 14.5, weight: FontWeight.w600, color: c.ink)),
                Text(contact.role, style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.inkFaint)),
              ]),
            ]),
          ),
          Container(height: 1, color: c.lineSoft),
          Expanded(
            child: g.threads[contactId]!.isEmpty
                ? Center(child: Text('No messages yet.', style: AppText.sans(size: 12.5, weight: FontWeight.w500, color: c.inkFaint)))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [for (final m in g.threads[contactId]!) MessageBubble(text: m.text, fromMe: m.fromMe)],
                  ),
          ),
        ]),
      ),
    );
  }
}
