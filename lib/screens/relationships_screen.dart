import 'package:flutter/material.dart' hide TimeOfDay;
import '../theme.dart';
import '../controller.dart';
import '../conversation/intents.dart';
import '../data.dart';
import '../widgets.dart';

/// Inbox row for a personal contact — warm-toned, subtle dot instead of a bold badge.
class PersonalConversationRow extends StatelessWidget {
  final PersonalContact contact;
  const PersonalConversationRow({super.key, required this.contact});

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final rel = g.relationships[contact.id]!;
    final thread = g.personalThreads[contact.id]!;
    final last = thread.isNotEmpty ? thread.last : null;
    final quiet = rel.goneQuiet || rel.resolved;

    return Opacity(
      opacity: quiet ? 0.5 : 1,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.personalSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.personalLine),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            g.openPersonalThread(contact.id);
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => PersonalThreadScreen(contactId: contact.id)));
          },
          child: Row(children: [
            ContactAvatar(contact.initials),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(contact.name, style: AppText.sans(size: 14, weight: FontWeight.w600, color: c.ink)),
                  const SizedBox(width: 4),
                  Text(moodEmoji(rel.mood), style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                  Text(contact.relation, style: AppText.sans(size: 10.5, weight: FontWeight.w500, color: c.inkFaint)),
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
            if (rel.unread && !quiet)
              Container(width: 5, height: 5, margin: const EdgeInsets.only(left: 8), decoration: BoxDecoration(shape: BoxShape.circle, color: c.personalDot)),
          ]),
        ),
      ),
    );
  }
}

class PersonalThreadScreen extends StatefulWidget {
  final String contactId;
  const PersonalThreadScreen({super.key, required this.contactId});

  @override
  State<PersonalThreadScreen> createState() => _PersonalThreadScreenState();
}

class _PersonalThreadScreenState extends State<PersonalThreadScreen> {
  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final contactId = widget.contactId;
    final contact = kPersonalContact[contactId]!;
    final rel = g.relationships[contactId]!;
    final thread = g.personalThreads[contactId]!;
    final quiet = rel.goneQuiet || rel.resolved || rel.isBlocked;

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
                Row(children: [
                  Text(contact.name, style: AppText.sans(size: 14.5, weight: FontWeight.w600, color: c.ink)),
                  const SizedBox(width: 4),
                  Text(moodEmoji(rel.mood), style: const TextStyle(fontSize: 12)),
                ]),
                Text(contact.relation, style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.inkFaint)),
              ]),
            ]),
          ),
          Container(height: 1, color: c.personalLine),
          Expanded(
            child: thread.isEmpty
                ? Center(child: Text('No messages yet.', style: AppText.sans(size: 12.5, weight: FontWeight.w500, color: c.inkFaint)))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [for (final m in thread) MessageBubble(text: m.text, fromMe: m.fromMe, warm: true)],
                  ),
          ),
          if (quiet)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Text(
                rel.goneQuiet
                    ? 'This thread has gone quiet.'
                    : rel.isBlocked
                        ? "They've blocked you."
                        : 'This conversation has run its course.',
                style: AppText.sans(size: 12, weight: FontWeight.w500, color: c.inkFaint),
              ),
            )
          else
            _ReplyTray(
              options: g.personalReplyOptions(contactId),
              rel: rel,
              timeOfDay: g.timeOfDay,
              onTap: (option) {
                if (option is IntentChip) {
                  g.sendIntent(contactId, option.intent);
                } else if (option is StoryChipOption) {
                  g.personalReplyAction(contactId, option.action);
                }
              },
            ),
        ]),
      ),
    );
  }
}

/// Horizontal scrolling tray of reply chips — two rows that scroll together
/// as one unit. Even-indexed chips go on the top row, odd-indexed on the
/// bottom, so both rows stay roughly the same length.
class _ReplyTray extends StatelessWidget {
  final List<ReplyOption> options;
  final RelationshipState rel;
  final TimeOfDay timeOfDay;
  final void Function(ReplyOption) onTap;
  const _ReplyTray({required this.options, required this.rel, required this.timeOfDay, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final top = [for (int i = 0; i < options.length; i += 2) options[i]];
    final bot = [for (int i = 1; i < options.length; i += 2) options[i]];

    List<Widget> buildRow(List<ReplyOption> items) => [
      for (int i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        _ReplyActionChip(
          label: items[i].displayLabel(rel, timeOfDay),
          onTap: () => onTap(items[i]),
        ),
      ],
    ];

    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.personalLine))),
      padding: const EdgeInsets.only(top: 12, bottom: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: buildRow(top)),
            if (bot.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: buildRow(bot)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReplyActionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ReplyActionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: c.personalSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.personalLine),
        ),
        child: Text(
          label,
          style: AppText.sans(size: 13, weight: FontWeight.w500, color: c.ink),
        ),
      ),
    );
  }
}
