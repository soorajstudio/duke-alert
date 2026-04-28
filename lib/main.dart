import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:telephony/telephony.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// ─── GLOBAL PERSISTENT STATE ────────────────────────────────
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);
final ValueNotifier<double> fontScaleNotifier = ValueNotifier(1.0);
// CHANGED: Default intro/boot color is now clean white/monochrome
final ValueNotifier<Color> colorNotifier = ValueNotifier(Colors.white);

// ─── FORWARD CONTACT MODEL ──────────────────────────────────
class ForwardContact {
  final String phone;
  final String method; // 'SMS' or 'InApp'

  const ForwardContact({required this.phone, required this.method});

  Map<String, dynamic> toJson() => {'phone': phone, 'method': method};
  factory ForwardContact.fromJson(Map<String, dynamic> j) =>
      ForwardContact(phone: j['phone'], method: j['method'] ?? 'SMS');
}

// ─── BACKGROUND SMS FORWARDER ────────────────────────────────
@pragma('vm:entry-point')
void autoForwardSMS(int id, Map<String, dynamic> params) {
  debugPrint("SHADOW TASK: Forwarding alert via SMS...");
  final telephony = Telephony.instance;
  final List<dynamic> contacts = jsonDecode(params['contacts'] ?? '[]');

  for (final c in contacts) {
    final phone = c['phone'] as String;
    final method = c['method'] as String;
    final title = params['title'] ?? 'Duke Alert';
    final body = params['body'] ?? '';

    if (phone.isEmpty) continue;

    if (method == 'InApp') {
      final uri = Uri(
        scheme: 'dukelert',
        host: 'alert',
        queryParameters: {'title': title, 'body': body},
      ).toString();
      telephony.sendSms(
        to: phone,
        message: 'DUKE ALERT (tap to open): $uri',
        isMultipart: true,
      );
    } else {
      telephony.sendSms(
        to: phone,
        message: 'DUKE ALERT — $title: $body',
        isMultipart: true,
      );
    }
  }
}

// ─── SNOOZE HANDLER ─────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> executeSnooze(NotificationResponse response) async {
  if (response.actionId == null || !response.actionId!.startsWith('snooze_')) {
    return;
  }

  String title = "Duke Alert";
  String body = "Snoozed Alert!";
  int snoozeMins = response.actionId == 'snooze_60' ? 60 : 5;

  if (response.payload != null && response.payload!.isNotEmpty) {
    final parts = response.payload!.split('||');
    if (parts.length >= 2) {
      title = parts.elementAt(0);
      body = parts.elementAt(1);
    }
  }

  try {
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Calcutta'));
    }
  } catch (e) {
    debugPrint("TZ Error: $e");
  }

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher')),
  );

  final scheduledDate = DateTime.now().add(Duration(minutes: snoozeMins));
  final snoozeId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  await plugin.zonedSchedule(
    id: snoozeId,
    title: "↻  $title",
    body: body,
    payload: response.payload,
    scheduledDate: tz.TZDateTime.from(scheduledDate, tz.local),
    notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails('duke_alert_v8', 'Duke Engine',
            importance: Importance.max, priority: Priority.high, playSound: true)),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
  );
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse r) => executeSnooze(r);

// ─── DEEP-LINK HANDLER (Phone B — In-App receive) ────────────
Future<void> _handleInAppDeepLink(FlutterLocalNotificationsPlugin plugin) async {
  try {
    final appLinks = AppLinks();
    final uri = await appLinks.getInitialLink();
    if (uri != null && uri.scheme == 'dukelert' && uri.host == 'alert') {
      final title = uri.queryParameters['title'] ?? 'Duke Alert';
      final body = uri.queryParameters['body'] ?? '';
      await plugin.show(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: '📲 $title',
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'duke_alert_v8', 'Duke Engine',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
    }

    appLinks.uriLinkStream.listen((uri) async {
      if (uri.scheme == 'dukelert' && uri.host == 'alert') {
        final title = uri.queryParameters['title'] ?? 'Duke Alert';
        final body = uri.queryParameters['body'] ?? '';
        await plugin.show(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: '📲 $title',
          body: body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'duke_alert_v8', 'Duke Engine',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
        );
      }
    });
  } catch (e) {
    debugPrint("Deep-link error: $e");
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AndroidAlarmManager.initialize();
  final prefs = await SharedPreferences.getInstance();
  themeNotifier.value = (prefs.getBool('isDark') ?? true) ? ThemeMode.dark : ThemeMode.light;
  fontScaleNotifier.value = prefs.getDouble('fontScale') ?? 1.0;
  // CHANGED: Default is now white
  colorNotifier.value = Color(prefs.getInt('themeColor') ?? Colors.white.toARGB32());

  try {
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Calcutta'));
    }
  } catch (e) {
    debugPrint("TZ: $e");
  }

  final notifPlugin = FlutterLocalNotificationsPlugin();
  await notifPlugin.initialize(
    settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher')),
  );

  await _handleInAppDeepLink(notifPlugin);

  runApp(const DukeAlertApp());
}

// ─── APP ROOT ────────────────────────────────────────────────
class DukeAlertApp extends StatelessWidget {
  const DukeAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: colorNotifier,
      builder: (_, Color currentColor, _) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeNotifier,
          builder: (_, ThemeMode currentMode, _) {
            return ValueListenableBuilder<double>(
              valueListenable: fontScaleNotifier,
              builder: (_, double currentScale, _) {
                return MaterialApp(
                  title: 'Duke Alert',
                  debugShowCheckedModeBanner: false,
                  theme: ThemeData.light(useMaterial3: true).copyWith(
                    colorScheme: ColorScheme.fromSeed(seedColor: currentColor),
                  ),
                  darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
                    colorScheme: ColorScheme.fromSeed(
                        seedColor: currentColor,
                        brightness: Brightness.dark),
                  ),
                  themeMode: currentMode,
                  builder: (context, child) {
                    return MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                          textScaler: TextScaler.linear(currentScale)),
                      child: child!,
                    );
                  },
                  home: const DukeAlertDashboard(),
                );
              },
            );
          },
        );
      },
    );
  }
}

// ─── DASHBOARD ───────────────────────────────────────────────
class DukeAlertDashboard extends StatefulWidget {
  const DukeAlertDashboard({super.key});
  @override
  State<DukeAlertDashboard> createState() => _DukeAlertDashboardState();
}

class _DukeAlertDashboardState extends State<DukeAlertDashboard> {
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;
  int _currentTabIndex = 0;
  int? _editingMainId;

  final TextEditingController _titleController = TextEditingController(text: "Duke Alert");
  final TextEditingController _bodyController = TextEditingController(text: "System check required!");
  final TextEditingController _manualDateController = TextEditingController(text: "${DateTime.now().day}");

  final List<ForwardContact> _forwardContacts = [];
  final List<Map<String, dynamic>> _activeTriggers = [];
  DateTime _oneTimeDate = DateTime.now();
  TimeOfDay _oneTimeTime = TimeOfDay.now();
  String _scheduleType = 'Daily';
  TimeOfDay _repeatTime = TimeOfDay.now();
  DateTime _calendarDate = DateTime.now();
  final List<String> _weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final List<String> _selectedDays = [];
  final List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final List<String> _selectedMonths = [];
  bool _useCustomSound = false;
  double _localFontScale = 1.0;

  // CHANGED: White is now the first option in the list
  final List<Color> _themeColors = [
    Colors.white, Colors.orange, Colors.blue, Colors.green,
    Colors.red, Colors.blueGrey, Colors.deepPurple
  ];

  @override
  void initState() {
    super.initState();
    _localFontScale = fontScaleNotifier.value;
    _initNotifications();
    _loadTriggers();
    _requestPermissions(); // Ask for SMS permissions safely on load
  }

  Future<void> _requestPermissions() async {
    final Telephony telephony = Telephony.instance;
    await telephony.requestPhoneAndSmsPermissions;
  }

  // ─── PERSISTENCE ─────────────────────────────────────────
  Future<void> _saveTriggers() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_activeTriggers.map((t) => {
          'id': t['id'],
          'subIds': t['subIds'],
          'title': t['title'],
          'body': t['body'],
          'subtitle': t['subtitle'],
          'type': t['type'],
          'nextFireDate': (t['nextFireDate'] as DateTime?)?.toIso8601String(),
          'rawTimeHour': (t['rawTime'] as TimeOfDay?)?.hour ?? 0,
          'rawTimeMinute': (t['rawTime'] as TimeOfDay?)?.minute ?? 0,
          'rawDays': t['rawDays'] ?? [],
          'rawMonths': t['rawMonths'] ?? [],
          'rawDate': t['rawDate'] ?? 1,
          'rawFullDate': (t['rawFullDate'] as DateTime?)?.toIso8601String(),
          'forwardContacts': (t['forwardContacts'] as List<ForwardContact>?)?.map((c) => c.toJson()).toList() ?? [],
        }).toList());
    await prefs.setString('saved_alarms', encoded);
  }

  Future<void> _loadTriggers() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('saved_alarms');
    if (saved != null) {
      final decoded = jsonDecode(saved) as List<dynamic>;
      setState(() {
        _activeTriggers.clear();
        _activeTriggers.addAll(decoded.map((t) => {
              'id': t['id'],
              'subIds': List<int>.from(t['subIds'] ?? []),
              'title': t['title'],
              'body': t['body'],
              'subtitle': t['subtitle'],
              'type': t['type'],
              'nextFireDate': t['nextFireDate'] != null ? DateTime.parse(t['nextFireDate']) : DateTime.now(),
              'rawTime': TimeOfDay(hour: t['rawTimeHour'] ?? 0, minute: t['rawTimeMinute'] ?? 0),
              'rawDays': List<String>.from(t['rawDays'] ?? []),
              'rawMonths': List<String>.from(t['rawMonths'] ?? []),
              'rawDate': t['rawDate'] ?? 1,
              'rawFullDate': t['rawFullDate'] != null ? DateTime.parse(t['rawFullDate']) : DateTime.now(),
              'forwardContacts': (t['forwardContacts'] as List<dynamic>?)?.map((c) => ForwardContact.fromJson(Map<String, dynamic>.from(c))).toList() ?? <ForwardContact>[],
            }));
      });
    }
  }

  // ─── NOTIFICATIONS INIT ──────────────────────────────────
  Future<void> _initNotifications() async {
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    await flutterLocalNotificationsPlugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: executeSnooze,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    final androidPlugin = flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
  }

  AndroidNotificationDetails _getNotificationDetails() => AndroidNotificationDetails(
        'duke_alert_v8', 'Duke Engine',
        importance: Importance.max,
        priority: Priority.high,
        sound: _useCustomSound ? const RawResourceAndroidNotificationSound('custom_alarm') : null,
        actions: const [
          AndroidNotificationAction('snooze_5', 'Snooze 5m'),
          AndroidNotificationAction('snooze_60', 'Snooze 1h'),
          AndroidNotificationAction('dismiss_action', 'Dismiss', cancelNotification: true),
        ],
      );

  String _generatePayload() => "${_titleController.text}||${_bodyController.text}";

  // ─── CANCEL ──────────────────────────────────────────────
  Future<void> _cancelTrigger(int mainId) async {
    final trigger = _activeTriggers.firstWhere((t) => t['id'] == mainId);
    for (int subId in trigger['subIds']) {
      await flutterLocalNotificationsPlugin.cancel(id: subId);
    }
    await AndroidAlarmManager.cancel(mainId);
    setState(() {
      _activeTriggers.removeWhere((t) => t['id'] == mainId);
      if (_editingMainId == mainId) _editingMainId = null;
    });
    await _saveTriggers();
  }

  // ─── LOAD FOR EDITING ─────────────────────────────────────
  void _loadTriggerForEditing(Map<String, dynamic> trigger) {
    setState(() {
      _editingMainId = trigger['id'];
      _titleController.text = trigger['title'];
      _bodyController.text = trigger['body'];
      _forwardContacts.clear();
      _forwardContacts.addAll(List<ForwardContact>.from(trigger['forwardContacts'] ?? []));

      if (trigger['type'] == 'OneTime') {
        _currentTabIndex = 0;
        _oneTimeDate = trigger['nextFireDate'];
        _oneTimeTime = TimeOfDay.fromDateTime(trigger['nextFireDate']);
      } else {
        _currentTabIndex = 1;
        _scheduleType = trigger['type'];
        _repeatTime = trigger['rawTime'];
        if (_scheduleType == 'Weekly') {
          _selectedDays..clear()..addAll(List<String>.from(trigger['rawDays'] ?? []));
        } else if (_scheduleType == 'Monthly') {
          _selectedMonths..clear()..addAll(List<String>.from(trigger['rawMonths'] ?? []));
          _manualDateController.text = trigger['rawDate'].toString();
        } else if (_scheduleType == 'Yearly') {
          _calendarDate = trigger['rawFullDate'];
        }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Editing Mode Active"), backgroundColor: Colors.blue));
  }

  // ─── ARM ONE-TIME ─────────────────────────────────────────
  Future<void> _armOneTimeEngine() async {
    if (_editingMainId != null) await _cancelTrigger(_editingMainId!);
    final now = DateTime.now();
    final scheduledDate = DateTime(_oneTimeDate.year, _oneTimeDate.month, _oneTimeDate.day, _oneTimeTime.hour, _oneTimeTime.minute);
    if (scheduledDate.isBefore(now)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cannot schedule in the past!"), backgroundColor: Colors.red));
      return;
    }

    final int mainId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id: mainId,
      title: _titleController.text,
      body: _bodyController.text,
      payload: _generatePayload(),
      scheduledDate: tz.TZDateTime.from(scheduledDate, tz.local),
      notificationDetails: NotificationDetails(android: _getNotificationDetails()),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );

    if (_forwardContacts.isNotEmpty) {
      await AndroidAlarmManager.oneShotAt(
        scheduledDate,
        mainId,
        autoForwardSMS,
        exact: true,
        wakeup: true,
        params: {
          'title': _titleController.text,
          'body': _bodyController.text,
          'contacts': jsonEncode(_forwardContacts.map((c) => c.toJson()).toList()),
        },
      );
    }

    setState(() {
      _activeTriggers.add({
        'id': mainId,
        'subIds': [mainId],
        'title': _titleController.text,
        'body': _bodyController.text,
        'subtitle': "One-Time: ${scheduledDate.day}/${scheduledDate.month}/${scheduledDate.year} at ${_oneTimeTime.format(context)}",
        'type': 'OneTime',
        'nextFireDate': scheduledDate,
        'forwardContacts': List<ForwardContact>.from(_forwardContacts),
      });
      _editingMainId = null;
      _forwardContacts.clear();
    });
    await _saveTriggers();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Strike Armed!"), backgroundColor: Colors.green));
  }

  // ─── ARM REPEATING ────────────────────────────────────────
  Future<void> _armRepeatingEngine() async {
    if (_scheduleType == 'Weekly' && _selectedDays.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select at least one day!"), backgroundColor: Colors.red));
      return;
    }
    if (_scheduleType == 'Monthly' && _selectedMonths.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select at least one month!"), backgroundColor: Colors.red));
      return;
    }
    if (_editingMainId != null) await _cancelTrigger(_editingMainId!);

    final int mainId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final List<int> subAlarmIds = [];
    String displaySubtitle = "";
    DateTime soonestDate = DateTime.now().add(const Duration(days: 365));

    if (_scheduleType == 'Daily') {
      soonestDate = _nextTime(_repeatTime);
      await _injectRepeating(mainId, soonestDate, DateTimeComponents.time);
      subAlarmIds.add(mainId);
      displaySubtitle = "Daily at ${_repeatTime.format(context)}";
    } else if (_scheduleType == 'Weekly') {
      for (String day in _selectedDays) {
        final dayIndex = _weekDays.indexOf(day) + 1;
        final subId = mainId + dayIndex;
        final d = _nextWeekday(dayIndex, _repeatTime);
        if (d.isBefore(soonestDate)) soonestDate = d;
        await _injectRepeating(subId, d, DateTimeComponents.dayOfWeekAndTime);
        subAlarmIds.add(subId);
      }
      displaySubtitle = "Weekly on ${_selectedDays.join(', ')}";
    } else if (_scheduleType == 'Monthly') {
      final targetDay = int.tryParse(_manualDateController.text) ?? 1;
      for (String month in _selectedMonths) {
        final monthIndex = _months.indexOf(month) + 1;
        final subId = mainId + monthIndex;
        final d = _nextDate(monthIndex, targetDay, _repeatTime);
        if (d.isBefore(soonestDate)) soonestDate = d;
        await _injectRepeating(subId, d, DateTimeComponents.dateAndTime);
        subAlarmIds.add(subId);
      }
      displaySubtitle = "Monthly on ${_selectedMonths.join(', ')} (${_manualDateController.text})";
    } else if (_scheduleType == 'Yearly') {
      soonestDate = _nextDate(_calendarDate.month, _calendarDate.day, _repeatTime);
      await _injectRepeating(mainId, soonestDate, DateTimeComponents.dateAndTime);
      subAlarmIds.add(mainId);
      displaySubtitle = "Yearly on ${_months[_calendarDate.month - 1]} ${_calendarDate.day}";
    }

    if (_forwardContacts.isNotEmpty) {
      await AndroidAlarmManager.oneShotAt(
        soonestDate,
        mainId,
        autoForwardSMS,
        exact: true,
        wakeup: true,
        params: {
          'title': _titleController.text,
          'body': _bodyController.text,
          'contacts': jsonEncode(_forwardContacts.map((c) => c.toJson()).toList()),
        },
      );
    }

    setState(() {
      _activeTriggers.add({
        'id': mainId,
        'subIds': subAlarmIds,
        'title': _titleController.text,
        'body': _bodyController.text,
        'subtitle': displaySubtitle,
        'type': _scheduleType,
        'nextFireDate': soonestDate,
        'rawTime': _repeatTime,
        'rawDays': List<String>.from(_selectedDays),
        'rawMonths': List<String>.from(_selectedMonths),
        'rawDate': int.tryParse(_manualDateController.text) ?? 1,
        'rawFullDate': _calendarDate,
        'forwardContacts': List<ForwardContact>.from(_forwardContacts),
      });
      _editingMainId = null;
      _forwardContacts.clear();
    });
    await _saveTriggers();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Patrol Armed!"), backgroundColor: Colors.green));
  }

  Future<void> _injectRepeating(int id, DateTime date, DateTimeComponents matchLogic) async {
    await flutterLocalNotificationsPlugin.zonedSchedule(
      id: id,
      title: _titleController.text,
      body: _bodyController.text,
      payload: _generatePayload(),
      scheduledDate: tz.TZDateTime.from(date, tz.local),
      notificationDetails: NotificationDetails(android: _getNotificationDetails()),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: matchLogic,
    );
  }

  DateTime _nextTime(TimeOfDay time) {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return d.isBefore(now) ? d.add(const Duration(days: 1)) : d;
  }

  DateTime _nextWeekday(int wDay, TimeOfDay time) {
    DateTime d = _nextTime(time);
    while (d.weekday != wDay) { d = d.add(const Duration(days: 1)); }
    return d;
  }

  DateTime _nextDate(int m, int d, TimeOfDay time) {
    final now = DateTime.now();
    final date = DateTime(now.year, m, d, time.hour, time.minute);
    return date.isBefore(now) ? DateTime(now.year + 1, m, d, time.hour, time.minute) : date;
  }

  // ─── FORWARD CONTACTS DIALOG ─────────────────────────────
  void _openForwardContactsDialog() {
    final phoneCtrl = TextEditingController();
    String selectedMethod = 'SMS';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.share_location, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Text("Forward Alert To",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ]),
                const SizedBox(height: 4),
                Text(
                  "SMS works on any phone. In-App works if the recipient also has Duke Alert installed.",
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.secondary),
                ),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'SMS', label: Text('SMS'), icon: Icon(Icons.sms, size: 16)),
                    ButtonSegment(value: 'InApp', label: Text('In-App (Duke)'), icon: Icon(Icons.notifications_active, size: 16)),
                  ],
                  selected: {selectedMethod},
                  onSelectionChanged: (s) => setSheet(() => selectedMethod = s.first),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]'))],
                      decoration: const InputDecoration(
                        labelText: "Phone number (e.g. +91 98765 43210)",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () {
                      final phone = phoneCtrl.text.trim();
                      if (phone.isEmpty) return;
                      setState(() {
                        _forwardContacts.add(ForwardContact(phone: phone, method: selectedMethod));
                      });
                      setSheet(() {});
                      phoneCtrl.clear();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text("Add"),
                  ),
                ]),
                const SizedBox(height: 16),
                if (_forwardContacts.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text("No contacts added yet.", style: TextStyle(fontStyle: FontStyle.italic)),
                    ),
                  )
                else
                  ..._forwardContacts.asMap().entries.map((entry) {
                    final i = entry.key;
                    final c = entry.value;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          c.method == 'InApp' ? Icons.notifications_active : Icons.sms,
                          color: c.method == 'InApp' ? Colors.deepPurple : Colors.teal,
                        ),
                        title: Text(c.phone, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(c.method == 'InApp' ? 'In-App (Duke)' : 'SMS'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: () {
                            setState(() => _forwardContacts.removeAt(i));
                            setSheet(() {});
                          },
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text("Done")),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  Widget _buildForwardContactsSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(children: [
          Text("FORWARD ALERT",
              style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 13)),
          const Spacer(),
          TextButton.icon(
            onPressed: _openForwardContactsDialog,
            icon: const Icon(Icons.add_call, size: 18),
            label: Text(_forwardContacts.isEmpty ? "Add Contacts" : "Edit Contacts (${_forwardContacts.length})"),
          ),
        ]),
        if (_forwardContacts.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _forwardContacts.map((c) {
              return Chip(
                avatar: Icon(
                  c.method == 'InApp' ? Icons.notifications_active : Icons.sms,
                  size: 16, color: c.method == 'InApp' ? Colors.deepPurple : Colors.teal,
                ),
                label: Text(c.phone, style: const TextStyle(fontSize: 12)),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () => setState(() => _forwardContacts.remove(c)),
              );
            }).toList(),
          )
        else
          Text("No contacts — alert stays local.", style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildSharedInputs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text("ALERT CONTENT", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        TextField(controller: _titleController, decoration: const InputDecoration(labelText: "Alert Title", border: OutlineInputBorder())),
        const SizedBox(height: 15),
        TextField(controller: _bodyController, decoration: const InputDecoration(labelText: "Message", border: OutlineInputBorder())),
        const SizedBox(height: 15),
        _buildForwardContactsSummary(),
      ],
    );
  }

  Widget _buildRadarList() {
    if (_activeTriggers.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 30),
          Text("SCHEDULED RADAR", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Center(child: Text("NO THREATS DETECTED", style: TextStyle(fontStyle: FontStyle.italic))),
        ],
      );
    }

    List<Map<String, dynamic>> sortedTriggers = List.from(_activeTriggers);
    sortedTriggers.sort((a, b) => (a['nextFireDate'] as DateTime).compareTo(b['nextFireDate'] as DateTime));

    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final endOfWeek = endOfToday.add(Duration(days: 7 - now.weekday));

    List<Widget> groupedItems = [
      const SizedBox(height: 30),
      Text("SCHEDULED RADAR", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
    ];

    String currentHeader = "";

    for (var trigger in sortedTriggers) {
      final nextFire = trigger['nextFireDate'] as DateTime;
      String sectionHeader = "LATER";
      if (nextFire.isBefore(endOfToday)) {
        sectionHeader = "TODAY";
      } else if (nextFire.isBefore(endOfWeek)) {
        sectionHeader = "THIS WEEK";
      }

      if (sectionHeader != currentHeader) {
        groupedItems.add(Padding(
          padding: const EdgeInsets.only(top: 15, bottom: 5),
          child: Text(sectionHeader, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.5, color: Colors.grey)),
        ));
        currentHeader = sectionHeader;
      }

      final contacts = (trigger['forwardContacts'] as List<ForwardContact>?) ?? [];

      groupedItems.add(Card(
        elevation: _editingMainId == trigger['id'] ? 4 : 1,
        color: _editingMainId == trigger['id'] ? Theme.of(context).colorScheme.primaryContainer : null,
        child: InkWell(
          onTap: () => _loadTriggerForEditing(trigger),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(trigger['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.green),
                          ),
                          child: const Text("ARMED", style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text(trigger['subtitle'], style: const TextStyle(fontSize: 13)),
                      Text("Payload: ${trigger['body']}", style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)),
                      if (contacts.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          children: contacts.map((c) {
                            return Chip(
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              avatar: Icon(
                                c.method == 'InApp' ? Icons.notifications_active : Icons.sms,
                                size: 14, color: c.method == 'InApp' ? Colors.deepPurple : Colors.teal,
                              ),
                              label: Text(c.phone, style: const TextStyle(fontSize: 11)),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () => _cancelTrigger(trigger['id'] as int)),
              ],
            ),
          ),
        ),
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: groupedItems);
  }

  Widget _buildOneTimeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("STRIKE CONFIGURATION", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Card(child: ListTile(title: const Text("Date"), subtitle: Text("${_oneTimeDate.day}/${_oneTimeDate.month}/${_oneTimeDate.year}", style: const TextStyle(fontWeight: FontWeight.bold)), onTap: () async { final p = await showDatePicker(context: context, initialDate: _oneTimeDate, firstDate: DateTime.now(), lastDate: DateTime(2100)); if (p != null) setState(() => _oneTimeDate = p); }))),
            Expanded(child: Card(child: ListTile(title: const Text("Time"), subtitle: Text(_oneTimeTime.format(context), style: const TextStyle(fontWeight: FontWeight.bold)), onTap: () async { final p = await showTimePicker(context: context, initialTime: _oneTimeTime); if (p != null) setState(() => _oneTimeTime = p); }))),
          ]),
          _buildSharedInputs(),
          SizedBox(
            width: double.infinity, height: 60,
            child: ElevatedButton.icon(
              onPressed: _armOneTimeEngine,
              icon: Icon(_editingMainId != null ? Icons.sync : Icons.bolt),
              label: Text(_editingMainId != null ? "UPDATE STRIKE" : "ARM STRIKE"),
              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white),
            ),
          ),
          _buildRadarList(),
        ],
      ),
    );
  }

  Widget _buildRepeatingTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("PATROL CONFIGURATION", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'Daily', label: Text('Daily')),
                ButtonSegment(value: 'Weekly', label: Text('Weekly')),
                ButtonSegment(value: 'Monthly', label: Text('Monthly')),
                ButtonSegment(value: 'Yearly', label: Text('Yearly')),
              ],
              selected: {_scheduleType},
              onSelectionChanged: (Set<String> newSelection) => setState(() => _scheduleType = newSelection.first),
            ),
          ),
          const SizedBox(height: 20),
          if (_scheduleType == 'Weekly')
            Wrap(spacing: 5.0, children: _weekDays.map((day) => FilterChip(label: Text(day), selected: _selectedDays.contains(day), onSelected: (bool selected) => setState(() { selected ? _selectedDays.add(day) : _selectedDays.remove(day); }))).toList()),
          if (_scheduleType == 'Monthly') ...[
            Wrap(spacing: 5.0, children: _months.map((month) => FilterChip(label: Text(month), selected: _selectedMonths.contains(month), onSelected: (bool selected) => setState(() { selected ? _selectedMonths.add(month) : _selectedMonths.remove(month); }))).toList()),
            const SizedBox(height: 15),
            TextField(controller: _manualDateController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Day (1-31)", border: OutlineInputBorder())),
          ],
          if (_scheduleType == 'Yearly')
            Card(child: ListTile(title: const Text("Pick Annual Date"), subtitle: Text("${_months[_calendarDate.month - 1]} ${_calendarDate.day}", style: const TextStyle(fontWeight: FontWeight.bold)), trailing: IconButton(icon: const Icon(Icons.calendar_month), onPressed: () async { final p = await showDatePicker(context: context, initialDate: _calendarDate, firstDate: DateTime(2000), lastDate: DateTime(2100)); if (p != null) { setState(() => _calendarDate = p); } }))),
          const SizedBox(height: 10),
          Card(child: ListTile(leading: Icon(Icons.alarm, color: Theme.of(context).colorScheme.primary), title: Text(_repeatTime.format(context), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), trailing: ElevatedButton(onPressed: () async { final p = await showTimePicker(context: context, initialTime: _repeatTime); if (p != null) { setState(() => _repeatTime = p); } }, child: const Text("SET TIME")))),
          _buildSharedInputs(),
          SizedBox(
            width: double.infinity, height: 60,
            child: ElevatedButton.icon(
              onPressed: _armRepeatingEngine,
              icon: Icon(_editingMainId != null ? Icons.sync : Icons.loop),
              label: Text(_editingMainId != null ? "UPDATE PATROL" : "ARM PATROL"),
              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white),
            ),
          ),
          _buildRadarList(),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    final isDark = themeNotifier.value == ThemeMode.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text("SYSTEM PREFERENCES", style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        SwitchListTile(
          title: const Text("Dark Mode (Tactical Theme)"),
          secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
          value: isDark,
          onChanged: (val) async {
            themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('isDark', val);
          },
        ),
        const Divider(),
        ListTile(
          title: const Text("Theme Accent Color"),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 10.0),
            child: Wrap(
              spacing: 12,
              children: _themeColors.map((color) {
                return GestureDetector(
                  onTap: () async {
                    colorNotifier.value = color;
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt('themeColor', color.toARGB32());
                  },
                  child: CircleAvatar(
                    backgroundColor: color,
                    radius: 18,
                    child: colorNotifier.value.toARGB32() == color.toARGB32()
                        ? const Icon(Icons.check, color: Colors.black, size: 20)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const Divider(),
        StatefulBuilder(builder: (context, setLocalState) {
          return ListTile(
            title: const Text("UI Text Scale"),
            subtitle: Slider(
              value: _localFontScale,
              min: 0.8,
              max: 1.5,
              divisions: 7,
              label: _localFontScale.toStringAsFixed(1),
              onChanged: (val) => setLocalState(() => _localFontScale = val),
              onChangeEnd: (val) async {
                fontScaleNotifier.value = val;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setDouble('fontScale', val);
              },
            ),
            leading: const Icon(Icons.format_size),
          );
        }),
        const Divider(),
        SwitchListTile(
          title: const Text("Override Audio Protocol"),
          subtitle: const Text("Requires custom_alarm.mp3 in raw folder"),
          secondary: const Icon(Icons.audiotrack),
          value: _useCustomSound,
          onChanged: (val) => setState(() => _useCustomSound = val),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("DUKE ALERT", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
        centerTitle: true,
      ),
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          _buildOneTimeTab(),
          _buildRepeatingTab(),
          _buildSettingsTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTabIndex,
        onTap: (index) => setState(() => _currentTabIndex = index),
        selectedItemColor: Theme.of(context).colorScheme.primary,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.gps_fixed), label: 'Strike'),
          BottomNavigationBarItem(
            icon: Badge(
                isLabelVisible: _activeTriggers.isNotEmpty,
                label: Text('${_activeTriggers.length}'),
                child: const Icon(Icons.radar)),
            label: 'Patrol',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}