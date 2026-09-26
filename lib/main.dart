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
import 'screens/vehicle_field_guide_screen.dart';

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
  bool _rivalWarningShowing = false;
  bool _shortfallShowing = false;
  bool _curveballShowing = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final g = AppScope.of(context);

    if (g.gameOver) return const GameOverScreen();

    // Blocks entry to Level 1 exactly once per session — the sighting text
    // deliberately never names what's actually coming, so this (plus the
    // persistent KEY legend on the home screen) is where that reading skill
    // gets taught before the response-window clock is running.
    if (g.level == 1 && !g.fieldGuideSeen) {
      return VehicleFieldGuideScreen(onDone: g.markFieldGuideSeen);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybePromote(context, g);
      _maybeShowAttachmentWarning(context, g);
      _maybeShowRivalWarning(context, g);
      _maybeShowCurveball(context, g);
      _maybeShowShortfallNotice(context, g);
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

  void _maybeShowRivalWarning(BuildContext context, CareerController g) {
    if (_rivalWarningShowing || g.pendingRivalWarning == null) return;
    _rivalWarningShowing = true;
    final c = AppColors.of(context);
    final warning = g.pendingRivalWarning!;
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
            Text('${g.rivalCrewName} is a problem', style: AppText.sans(size: 18, weight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 10),
            Text(warning, style: AppText.sans(size: 13.5, weight: FontWeight.w500, color: c.inkSoft, height: 1.5)),
            const SizedBox(height: 18),
            AppButton(
              kind: BtnKind.ghost,
              full: true,
              height: 48,
              onTap: () {
                g.resolveRivalWarning('pay');
                Navigator.pop(ctx);
              },
              child: const Text('Pay them off'),
            ),
            const SizedBox(height: 10),
            AppButton(
              kind: BtnKind.danger,
              full: true,
              height: 48,
              onTap: () {
                g.resolveRivalWarning('retaliate');
                Navigator.pop(ctx);
              },
              child: const Text('Send a message back'),
            ),
            const SizedBox(height: 10),
            AppButton(
              kind: BtnKind.ghost,
              full: true,
              height: 48,
              onTap: () {
                g.resolveRivalWarning('ignore');
                Navigator.pop(ctx);
              },
              child: const Text('Ignore it'),
            ),
          ]),
        ),
      ),
    ).then((_) => _rivalWarningShowing = false);
  }

  /// The night's one curveball on the Level 3 route — a forced choice with
  /// each option's price spelled out, so it reads as a decision, not a trap.
  void _maybeShowCurveball(BuildContext context, CareerController g) {
    final kind = g.pendingCurveball;
    if (_curveballShowing || kind == null || _rivalWarningShowing || g.pendingRivalWarning != null) return;
    _curveballShowing = true;
    final c = AppColors.of(context);
    final isPolice = kind == 'police';
    final targetName = g.curveballTargetId == null ? '' : kCollectionRoute.firstWhere((t) => t.id == g.curveballTargetId).name;
    final title = isPolice ? 'Police activity' : '${g.rivalCrewName} showed up';
    final body = isPolice
        ? 'A patrol car keeps circling the block. Wait it out, or keep working the route with it out there.'
        : '${g.rivalCrewName} are working $targetName right now — one of your stops.';

    Widget choice(BuildContext ctx, String label, String cost, String value, {bool danger = false}) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: AppButton(
            kind: danger ? BtnKind.danger : BtnKind.ghost,
            full: true,
            height: null,
            onTap: () {
              g.resolveCurveball(value);
              Navigator.pop(ctx);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                Text(label, style: AppText.sans(size: 14, weight: FontWeight.w700, color: danger ? c.neg : c.ink)),
                const SizedBox(height: 2),
                Text(cost, textAlign: TextAlign.center, style: AppText.sans(size: 11.5, weight: FontWeight.w500, color: c.inkSoft, height: 1.35)),
              ]),
            ),
          ),
        );

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
            Text(title.toUpperCase(), style: AppText.sans(size: 12, weight: FontWeight.w700, color: c.warn, spacing: 1.2)),
            const SizedBox(height: 8),
            Text(body, style: AppText.sans(size: 13.5, weight: FontWeight.w500, color: c.inkSoft, height: 1.5)),
            const SizedBox(height: 8),
            if (isPolice) ...[
              choice(ctx, 'Lay low', '−${CareerController.kLayLowSeconds}s of the night · police heat −${CareerController.kLayLowHeatRelief.round()}', 'lay_low'),
              choice(ctx, 'Keep collecting', 'No time lost · police heat +${CareerController.kKeepGoingHeat.round()}, suspicion +2', 'keep_going', danger: true),
            ] else ...[
              choice(ctx, 'Confront them', '−${CareerController.kConfrontSeconds}s · coin flip: they back off (rival −10), or they dig in and skim $targetName (rival +8, heat +5)', 'confront', danger: true),
              choice(ctx, 'Let it go', '$targetName pays ${(CareerController.kFactionCutFraction * 100).round()}% less from now on · rival −6', 'let_go'),
            ],
          ]),
        ),
      ),
    ).then((_) => _curveballShowing = false);
  }

  void _maybeShowShortfallNotice(BuildContext context, CareerController g) {
    if (_shortfallShowing || g.shortfallNotice == null) return;
    _shortfallShowing = true;
    final c = AppColors.of(context);
    final notice = g.shortfallNotice!;
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
            Text('Short this week', style: AppText.sans(size: 18, weight: FontWeight.w700, color: c.neg)),
            const SizedBox(height: 10),
            Text(notice, style: AppText.sans(size: 13.5, weight: FontWeight.w500, color: c.inkSoft, height: 1.5)),
            const SizedBox(height: 18),
            AppButton(
              kind: BtnKind.dark,
              full: true,
              height: 48,
              onTap: () {
                g.acknowledgeShortfall();
                Navigator.pop(ctx);
              },
              child: const Text('Understood'),
            ),
          ]),
        ),
      ),
    ).then((_) => _shortfallShowing = false);
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
            Text(_promotionText(fromLevel) + _promotionShortWeekNote(fromLevel, g), style: AppText.sans(size: 13.5, weight: FontWeight.w500, color: c.inkSoft, height: 1.5)),
            const SizedBox(height: 18),
            if (fromLevel == 3)
              for (final path in kCareerPaths) ...[
                AppButton(
                  kind: BtnKind.ghost,
                  full: true,
                  height: null,
                  onTap: () {
                    g.acceptPromotion(path: path.id);
                    Navigator.pop(ctx);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(path.label, style: AppText.sans(size: 14, weight: FontWeight.w700, color: c.ink)),
                      const SizedBox(height: 4),
                      Text(path.description, style: AppText.sans(size: 12, weight: FontWeight.w500, color: c.inkSoft, height: 1.4)),
                    ]),
                  ),
                ),
                if (path != kCareerPaths.last) const SizedBox(height: 10),
              ]
            else
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

  /// Level 3's short weeks follow the player up — said out loud so the
  /// suspicion they carry into Level 4 isn't a surprise.
  String _promotionShortWeekNote(int fromLevel, CareerController g) {
    if (fromLevel != 3 || g.collectorShortWeeks == 0) return '';
    final weeks = g.collectorShortWeeks;
    return '\n\nBut you came up short $weeks ${weeks == 1 ? 'week' : 'weeks'} on the way — the new boss has heard. '
        'You start Level 4 with +${g.promotionCarryOver.round()} suspicion.';
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
