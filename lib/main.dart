import 'package:flutter/material.dart';
import 'theme.dart';
import 'controller.dart';
import 'data.dart';
import 'widgets.dart';
import 'screens/home_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/game_over_screen.dart';
import 'screens/level2_transport_screen.dart';
import 'screens/level3_collector_screen.dart';
import 'screens/level4_cell_leader_screen.dart';
import 'screens/level4_crew_screen.dart';
import 'screens/level4_territory_screen.dart';
import 'screens/strategic_screen.dart';
import 'screens/strategic_org_screen.dart';
import 'screens/strategic_territory_screen.dart';

void main() => runApp(const MeridianApp());

class MeridianApp extends StatefulWidget {
  const MeridianApp({super.key});
  @override
  State<MeridianApp> createState() => _MeridianAppState();
}

class _MeridianAppState extends State<MeridianApp> {
  final controller = CareerController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: appThemeData(AppColors.standard()),
            home: const _Root(),
          );
        },
      ),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  int tab = 0;
  bool _promotionShowing = false;
  bool _attachmentShowing = false;
  bool _tutorialBannerShowing = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final g = AppScope.of(context);

    if (g.gameOver) return const GameOverScreen();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybePromote(context, g);
      _maybeShowAttachmentWarning(context, g);
      _maybeShowTutorialBanner(context, g);
    });

    final tabs = _tabsForLevel(g.level);
    if (tab >= tabs.length) tab = 0;
    final anyPersonalUnread = g.relationships.values.any((r) => r.unread);

    return Scaffold(
      backgroundColor: c.appBg,
      body: SafeArea(
        bottom: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(anim), child: child),
          ),
          child: KeyedSubtree(key: ValueKey('${g.level}-$tab'), child: tabs[tab].screen),
        ),
      ),
      bottomNavigationBar: _TabBar(
        index: tab,
        tabs: tabs,
        unread: g.unread || anyPersonalUnread,
        onTap: (i) {
          if (tabs[i].label == 'MESSAGES' && g.unread) g.markMessagesRead();
          setState(() => tab = i);
        },
      ),
    );
  }

  void _maybeShowTutorialBanner(BuildContext context, CareerController g) {
    final lvl = g.pendingTutorialBannerLevel;
    if (_tutorialBannerShowing || lvl == null) return;
    _tutorialBannerShowing = true;
    g.consumeTutorialBanner();
    showTutorialNotificationBanner(
      context,
      lvl,
      onOpen: () {
        g.markMessagesRead();
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChatThreadScreen(contactId: 'handler')));
      },
    ).then((_) => _tutorialBannerShowing = false);
  }

  void _maybeShowAttachmentWarning(BuildContext context, CareerController g) {
    if (_attachmentShowing || g.attachmentWarningContactId == null) return;
    _attachmentShowing = true;
    final c = AppColors.of(context);
    final contactId = g.attachmentWarningContactId!;
    final contact = kPersonalContact[contactId]!;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.line)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your boss noticed', style: AppText.sans(size: 18, weight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 10),
            Text(
              "You've been distracted lately — texting ${contact.name} more than the work. He says attachments like that get people killed, yours or theirs.",
              style: AppText.sans(size: 13.5, weight: FontWeight.w500, color: c.inkSoft, height: 1.5),
            ),
            const SizedBox(height: 18),
            AppButton(
              kind: BtnKind.danger,
              full: true,
              height: 48,
              onTap: () {
                g.resolveAttachmentWarning('cut_off');
                Navigator.pop(ctx);
              },
              child: Text('Cut ${contact.name} off'),
            ),
            const SizedBox(height: 10),
            AppButton(
              kind: BtnKind.ghost,
              full: true,
              height: 48,
              onTap: () {
                g.resolveAttachmentWarning('reassure');
                Navigator.pop(ctx);
              },
              child: const Text('Reassure the boss'),
            ),
            const SizedBox(height: 10),
            AppButton(
              kind: BtnKind.ghost,
              full: true,
              height: 48,
              onTap: () {
                g.resolveAttachmentWarning('ignore');
                Navigator.pop(ctx);
              },
              child: const Text('Ignore it'),
            ),
          ]),
        ),
      ),
    ).then((_) => _attachmentShowing = false);
  }

  void _maybePromote(BuildContext context, CareerController g) {
    if (_promotionShowing || !g.promotionAvailable) return;
    _promotionShowing = true;
    final c = AppColors.of(context);
    final fromLevel = g.level;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.line)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Promotion', style: AppText.sans(size: 18, weight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 10),
            Text(_promotionText(fromLevel), style: AppText.sans(size: 13.5, weight: FontWeight.w500, color: c.inkSoft, height: 1.5)),
            const SizedBox(height: 18),
            AppButton(
              full: true,
              height: 48,
              onTap: () {
                g.acceptPromotion();
                Navigator.pop(ctx);
              },
              child: const Text('Take the job'),
            ),
          ]),
        ),
      ),
    ).then((_) => _promotionShowing = false);
  }

  String _promotionText(int fromLevel) {
    switch (fromLevel) {
      case 1:
        return "You've kept your mouth shut and your eyes open. The plaza boss wants you moving product, not just watching the road.";
      case 2:
        return "Every run's landed clean. They want you off the road and running collections instead.";
      case 3:
        return "You've never come up short. The boss wants you running a cell, not just a route.";
      case 4:
        return "Your numbers are the best in the region. Time to stop managing a corner and start managing corners.";
      case 5:
        return "The state needs a new boss. You've earned a seat at that table.";
      case 6:
        return "The old leader is gone. The empire needs someone who already knows how to run it.";
      default:
        return "You've been promoted.";
    }
  }

  List<_TabDef> _tabsForLevel(int level) {
    if (level <= 3) {
      return [
        _TabDef('HOME', level == 1 ? const HomeScreen() : level == 2 ? const TransportScreen() : const CollectorScreen(),
            (color) => HomeGlyph(color)),
        _TabDef('MESSAGES', const MessagesScreen(), (color) => MessagesGlyph(color)),
        _TabDef('CONTACTS', const ContactsScreen(), (color) => ContactsGlyph(color)),
        _TabDef('SETTINGS', const SettingsScreen(), (color) => SettingsGlyph(color)),
      ];
    }
    if (level == 4) {
      return [
        _TabDef('HOME', const CellLeaderScreen(), (color) => HomeGlyph(color)),
        _TabDef('MESSAGES', const MessagesScreen(), (color) => MessagesGlyph(color)),
        _TabDef('CREW', const Level4CrewScreen(), (color) => Icon(Icons.groups_outlined, size: 18, color: color)),
        _TabDef('TERRITORY', const Level4TerritoryScreen(), (color) => Icon(Icons.map_outlined, size: 18, color: color)),
        _TabDef('SETTINGS', const SettingsScreen(), (color) => SettingsGlyph(color)),
      ];
    }
    return [
      _TabDef('HOME', const StrategicScreen(), (color) => HomeGlyph(color)),
      _TabDef('MESSAGES', const MessagesScreen(), (color) => MessagesGlyph(color)),
      _TabDef('ORG', const StrategicOrgScreen(), (color) => Icon(Icons.groups_outlined, size: 18, color: color)),
      _TabDef('TERRITORY', const StrategicTerritoryScreen(), (color) => Icon(Icons.public, size: 18, color: color)),
      _TabDef('SETTINGS', const SettingsScreen(), (color) => SettingsGlyph(color)),
    ];
  }
}

class _TabDef {
  final String label;
  final Widget screen;
  final Widget Function(Color color) glyph;
  _TabDef(this.label, this.screen, this.glyph);
}

class _TabBar extends StatelessWidget {
  final int index;
  final List<_TabDef> tabs;
  final bool unread;
  final ValueChanged<int> onTap;
  const _TabBar({required this.index, required this.tabs, required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(color: c.navBg, border: Border(top: BorderSide(color: c.lineSoft))),
      padding: EdgeInsets.only(top: 10, bottom: MediaQuery.of(context).padding.bottom + 10),
      child: Row(
        children: [
          for (int i = 0; i < tabs.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  tabs[i].label == 'MESSAGES' && unread
                      ? MessagesGlyph(i == index ? c.ink : c.inkFaint, unread: true)
                      : tabs[i].glyph(i == index ? c.ink : c.inkFaint),
                  const SizedBox(height: 5),
                  Text(tabs[i].label, style: AppText.sans(size: 9, weight: i == index ? FontWeight.w600 : FontWeight.w500, color: i == index ? c.ink : c.inkFaint, spacing: 0.4)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
