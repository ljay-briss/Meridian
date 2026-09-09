import 'package:flutter/material.dart' hide TimeOfDay;
import 'package:flutter/services.dart' show FilteringTextInputFormatter, LengthLimitingTextInputFormatter;
import '../theme.dart';
import '../controller.dart';
import '../conversation/intents.dart';
import '../conversation/reply_tray.dart';
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
  // Whether the reply tray is showing every eligible option (see
  // CareerController.personalReplyOptions's `expanded` param) instead of
  // just the curated handful. Lives here, not in _ReplyTray, because it has
  // to survive that widget being rebuilt with a fresh `options` list on
  // every message send — a reply always collapses the tray back down
  // (see the onTap handler below), so this only needs to reset implicitly
  // between screens, not be persisted anywhere.
  bool _trayExpanded = false;

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
              options: g.personalReplyOptions(contactId, expanded: _trayExpanded),
              rel: rel,
              timeOfDay: g.timeOfDay,
              expanded: _trayExpanded,
              onToggleExpanded: () => setState(() => _trayExpanded = !_trayExpanded),
              onTap: (option) {
                if (option is IntentChip) {
                  g.sendIntent(contactId, option.intent);
                } else if (option is StoryChipOption) {
                  g.personalReplyAction(contactId, option.action);
                } else if (option is MoneyAskChipOption) {
                  _showAskForMoneyDialog(context, g, contactId);
                }
                // Sending a reply changes the whole context (topic,
                // mood, pending question), so whatever the expanded menu
                // was showing is already stale — collapse back to the
                // curated tray for the next turn rather than leaving a
                // long, now-outdated list on screen.
                if (_trayExpanded) setState(() => _trayExpanded = false);
              },
            ),
        ]),
      ),
    );
  }
}

/// "(Ask for Money)" flow — the one reply option that needs a real number
/// from the player instead of a pre-written phrasing, so it opens this
/// dialog rather than sending immediately like every other chip. Handing off
/// to [CareerController.resolveMoneyAsk] once a positive amount is entered.
void _showAskForMoneyDialog(BuildContext context, CareerController g, String contactId) {
  final c = AppColors.of(context);
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.line)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: _AskForMoneyDialogBody(
        onSend: (amount) {
          g.resolveMoneyAsk(contactId, amount);
          Navigator.pop(ctx);
        },
      ),
    ),
  );
}

class _AskForMoneyDialogBody extends StatefulWidget {
  final void Function(int amount) onSend;
  const _AskForMoneyDialogBody({required this.onSend});
  @override
  State<_AskForMoneyDialogBody> createState() => _AskForMoneyDialogBodyState();
}

class _AskForMoneyDialogBodyState extends State<_AskForMoneyDialogBody> {
  final _controller = TextEditingController();
  int? _amount;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Ask Mamá for money', style: AppText.sans(size: 18, weight: FontWeight.w700, color: c.ink)),
        const SizedBox(height: 10),
        Text('How much do you need?', style: AppText.sans(size: 13.5, weight: FontWeight.w500, color: c.inkSoft, height: 1.5)),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(color: c.sunken, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            Text('\$', style: AppText.sans(size: 16, weight: FontWeight.w600, color: c.inkFaint)),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                style: AppText.sans(size: 16, weight: FontWeight.w600, color: c.ink),
                decoration: InputDecoration(border: InputBorder.none, hintText: '0', hintStyle: AppText.sans(size: 16, weight: FontWeight.w600, color: c.inkFaint)),
                onChanged: (v) => setState(() => _amount = int.tryParse(v)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: AppButton(kind: BtnKind.ghost, full: true, height: 48, onTap: () => Navigator.pop(context), child: const Text('Cancel'))),
          const SizedBox(width: 10),
          Expanded(
            child: AppButton(
              full: true,
              height: 48,
              onTap: (_amount != null && _amount! > 0) ? () => widget.onSend(_amount!) : null,
              child: const Text('Send'),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// The reply tray, in one of two layouts:
/// - Collapsed (default): a horizontal scrolling two-row strip, same as
///   before — even-indexed chips on top, odd-indexed on the bottom, so both
///   rows stay roughly the same length. A trailing "More options" chip is
///   appended after [options] so it always lands at the very end of
///   whichever row that works out to.
/// - Expanded ([expanded] true): every chip [options] holds (already
///   computed as the full eligible set by the caller — see
///   CareerController.personalReplyOptions's `expanded` param) laid out as a
///   wrapping grid in a height-capped, vertically scrolling area, so a large
///   catalog doesn't push the whole message thread off screen. A "Show
///   fewer" chip sits first so it's always reachable without scrolling.
class _ReplyTray extends StatelessWidget {
  final List<ReplyOption> options;
  final RelationshipState rel;
  final TimeOfDay timeOfDay;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final void Function(ReplyOption) onTap;
  const _ReplyTray({
    required this.options,
    required this.rel,
    required this.timeOfDay,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.personalLine))),
      padding: const EdgeInsets.only(top: 12, bottom: 16),
      child: expanded ? _buildExpanded(context) : _buildCollapsed(context),
    );
  }

  Widget _buildCollapsed(BuildContext context) {
    final top = <ReplyOption?>[for (int i = 0; i < options.length; i += 2) options[i]];
    final bot = <ReplyOption?>[for (int i = 1; i < options.length; i += 2) options[i]];
    // The toggle always lands in whichever row is currently shorter, so it
    // stays visually at the tail end of the tray rather than always forcing
    // a lonely second row into existence.
    (bot.length <= top.length ? bot : top).add(null);

    List<Widget> buildRow(List<ReplyOption?> items) => [
      for (int i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        items[i] == null
            ? _ReplyExpandChip(label: 'More options', icon: Icons.expand_more, onTap: onToggleExpanded)
            : _ReplyActionChip(label: items[i]!.displayLabel(rel, timeOfDay), onTap: () => onTap(items[i]!)),
      ],
    ];

    return SingleChildScrollView(
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
    );
  }

  Widget _buildExpanded(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ReplyExpandChip(label: 'Show fewer', icon: Icons.expand_less, onTap: onToggleExpanded),
            for (final o in options) _ReplyActionChip(label: o.displayLabel(rel, timeOfDay), onTap: () => onTap(o)),
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
        // Deliberately no `alignment` here: Container only shrink-wraps to
        // its child under UNBOUNDED incoming constraints (fine under this
        // chip's original Row usage) — with `alignment` set, it instead
        // EXPANDS to fill any BOUNDED constraint it's given, which is
        // exactly what Wrap hands each child (loose but bounded by the
        // wrap's own width), stretching every chip to full width. See
        // Container's own doc comment on `alignment` + bounded constraints.
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

/// The tray's expand/collapse control — visually distinct from
/// [_ReplyActionChip] (a subdued fill instead of the card surface, plus a
/// chevron icon) so it reads as "adjust the menu" rather than as one more
/// thing Mama could be told.
class _ReplyExpandChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _ReplyExpandChip({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        // See _ReplyActionChip's matching comment — no `alignment` here on
        // purpose, so this stays shrink-wrapped under Wrap's bounded
        // per-child constraints instead of stretching to fill the row.
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.sunken,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.personalLine),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: c.inkFaint),
          const SizedBox(width: 4),
          Text(label, style: AppText.sans(size: 13, weight: FontWeight.w500, color: c.inkFaint)),
        ]),
      ),
    );
  }
}
