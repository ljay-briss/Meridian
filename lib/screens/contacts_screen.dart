import 'package:flutter/material.dart';
import '../theme.dart';
import '../data.dart';
import '../widgets.dart';
import 'messages_screen.dart';
import 'relationships_screen.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        const ScreenHead('Contacts'),
        for (final contact in kContacts) ...[
          AppCard(
            padding: const EdgeInsets.all(14),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadScreen(contactId: contact.id))),
            child: Row(children: [
              ContactAvatar(contact.initials),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(contact.name, style: AppText.sans(size: 14.5, weight: FontWeight.w600, color: c.ink)),
                  const SizedBox(height: 2),
                  Text(contact.role, style: AppText.sans(size: 11.5, weight: FontWeight.w500, color: c.inkFaint)),
                ]),
              ),
              Icon(Icons.chevron_right, size: 18, color: c.inkFaint),
            ]),
          ),
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
