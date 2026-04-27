import 'dart:convert';
import 'package:telephony/telephony.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// GLOBAL PERSISTENT STATE
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);
final ValueNotifier<double> fontScaleNotifier = ValueNotifier(1.0);
final ValueNotifier<Color> colorNotifier = ValueNotifier(Colors.orange);
// --- THE AUTO-FORWARD SMS ENGINE ---
@pragma('vm:entry-point')
void autoForwardSMS(int id, Map<String, dynamic> params) {
  debugPrint("SHADOW TASK WAKING UP: Forwarding SMS...");
  
  final Telephony telephony = Telephony.instance;
  String targetPhone = params['phone'] ?? "";
  String message = params['message'] ?? "DUKE ALERT: System Check!";

  if (targetPhone.isNotEmpty) {
    telephony.sendSms(
      to: targetPhone,
      message: message,
      isMultipart: true, // Allows long messages
    );
  }
}
// --- THE BACKGROUND SNOOZE ENGINE ---
@pragma('vm:entry-point')
Future<void> executeSnooze(NotificationResponse response) async {
  if (response.actionId != null && response.actionId!.startsWith('snooze_')) {
    String title = "Duke Alert";
    String body = "Snoozed Alert!";
    int snoozeMins = response.actionId == 'snooze_60' ? 60 : 5;

    if (response.payload != null && response.payload!.isNotEmpty) {
      final parts = response.payload!.split('||');
      if (parts.length >= 2) { 
        // Using elementAt to prevent bracket-dropping bugs!
        title = parts.elementAt(0); 
        body = parts.elementAt(1); 
      }
    }
    
    try { 
      tz.initializeTimeZones(); 
      try { 
        tz.setLocalLocation(tz.getLocation('Asia/Kolkata')); 
      } catch (e) { 
        tz.setLocalLocation(tz.getLocation('Asia/Calcutta')); 
      } 
    } catch (e) {
      debugPrint("TZ Error: $e");
    }

    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    
    final scheduledDate = DateTime.now().add(Duration(minutes: snoozeMins));
    final snoozeId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    
    await plugin.zonedSchedule(
      id: snoozeId, title: "↻  $title", body: body, payload: response.payload,
      scheduledDate: tz.TZDateTime.from(scheduledDate, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails('duke_alert_v8', 'Duke Engine', importance: Importance.max, priority: Priority.high, playSound: true)),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse r) => executeSnooze(r);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AndroidAlarmManager.initialize(); // ADD THIS LINE
  final prefs = await SharedPreferences.getInstance();
  themeNotifier.value = (prefs.getBool('isDark') ?? true) ? ThemeMode.dark : ThemeMode.light;
  fontScaleNotifier.value = prefs.getDouble('fontScale') ?? 1.0;
  colorNotifier.value = Color(prefs.getInt('themeColor') ?? Colors.orange.value);

  try { 
    tz.initializeTimeZones(); 
    try { tz.setLocalLocation(tz.getLocation('Asia/Kolkata')); } 
    catch (_) { tz.setLocalLocation(tz.getLocation('Asia/Calcutta')); } 
  } catch (e) { debugPrint("TZ: $e"); }
  
  runApp(const DukeAlertApp());
}

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
                    colorScheme: ColorScheme.fromSeed(seedColor: currentColor, brightness: Brightness.dark),
                  ),
                  themeMode: currentMode,
                  builder: (context, child) {
                    return MediaQuery(
                      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(currentScale)),
                      child: child!,
                    );
                  },
                  home: const DukeAlertDashboard(),
                );
              },
            );
          },
        );
      }
    );
  }
}

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

  final List<Color> _themeColors = [Colors.orange, Colors.blue, Colors.green, Colors.red, Colors.blueGrey, Colors.deepPurple];

  @override
  void initState() {
    super.initState();
    _localFontScale = fontScaleNotifier.value;
    _initNotifications();
    _loadTriggers(); // Loads alarms from hard drive!
  }

  // --- MEMORY BANK ---
  Future<void> _saveTriggers() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_activeTriggers.map((t) => {
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
    }).toList());
    await prefs.setString('saved_alarms', encoded);
  }

  Future<void> _loadTriggers() async {
    final prefs = await SharedPreferences.getInstance();
    final String? saved = prefs.getString('saved_alarms');
    if (saved != null) {
      final List<dynamic> decoded = jsonDecode(saved);
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
        }).toList());
      });
    }
  }

  Future<void> _initNotifications() async {
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    await flutterLocalNotificationsPlugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (NotificationResponse details) => executeSnooze(details),
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    final androidPlugin = flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
  }

  AndroidNotificationDetails _getNotificationDetails() => AndroidNotificationDetails(
    'duke_alert_v8', 'Duke Engine', importance: Importance.max, priority: Priority.high,
    sound: _useCustomSound ? const RawResourceAndroidNotificationSound('custom_alarm') : null,
    actions: const [
      AndroidNotificationAction('snooze_5', 'Snooze 5m'),
      AndroidNotificationAction('snooze_60', 'Snooze 1h'),
      AndroidNotificationAction('dismiss_action', 'Dismiss', cancelNotification: true),
    ],
  );

  String _generatePayload() => "${_titleController.text}||${_bodyController.text}";

  Future<void> _cancelTrigger(int mainId) async {
    final trigger = _activeTriggers.firstWhere((t) => t['id'] == mainId);
    for (int subId in trigger['subIds']) { await flutterLocalNotificationsPlugin.cancel(id: subId); }
    setState(() {
      _activeTriggers.removeWhere((t) => t['id'] == mainId);
      if (_editingMainId == mainId) _editingMainId = null;
    });
    await _saveTriggers();
  }

  void _loadTriggerForEditing(Map<String, dynamic> trigger) {
    setState(() {
      _editingMainId = trigger['id'];
      _titleController.text = trigger['title'];
      _bodyController.text = trigger['body'];
      
      if (trigger['type'] == 'OneTime') {
        _currentTabIndex = 0;
        _oneTimeDate = trigger['nextFireDate'];
        _oneTimeTime = TimeOfDay.fromDateTime(trigger['nextFireDate']);
      } else {
        _currentTabIndex = 1;
        _scheduleType = trigger['type'];
        _repeatTime = trigger['rawTime'];
        if (_scheduleType == 'Weekly') { _selectedDays.clear(); _selectedDays.addAll(List<String>.from(trigger['rawDays'] ?? [])); } 
        else if (_scheduleType == 'Monthly') { _selectedMonths.clear(); _selectedMonths.addAll(List<String>.from(trigger['rawMonths'] ?? [])); _manualDateController.text = trigger['rawDate'].toString(); } 
        else if (_scheduleType == 'Yearly') { _calendarDate = trigger['rawFullDate']; }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Editing Mode Active"), backgroundColor: Colors.blue));
  }

  Future<void> _armOneTimeEngine() async {
    if (_editingMainId != null) await _cancelTrigger(_editingMainId!);
    final now = DateTime.now();
    DateTime scheduledDate = DateTime(_oneTimeDate.year, _oneTimeDate.month, _oneTimeDate.day, _oneTimeTime.hour, _oneTimeTime.minute);
    if (scheduledDate.isBefore(now)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cannot schedule in the past!"), backgroundColor: Colors.red)); return; }

    final int mainId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await flutterLocalNotificationsPlugin.zonedSchedule(
      id: mainId, title: _titleController.text, body: _bodyController.text, payload: _generatePayload(),
      scheduledDate: tz.TZDateTime.from(scheduledDate, tz.local), notificationDetails: NotificationDetails(android: _getNotificationDetails()), androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
    // THE SHADOW TASK: Auto-Forwarding via SMS
    // TODO: In V8.3, you should add a TextField to the UI so the user can type the target phone number. 
    // For now, replace this with your actual phone number to test it!
    String targetPhoneNumber = "+917593816280"; 

    await AndroidAlarmManager.oneShotAt(
      scheduledDate,
      mainId, // We use the same ID so we can track it
      autoForwardSMS,
      exact: true,
      wakeup: true,
      params: {
        'phone': targetPhoneNumber,
        'message': 'DUKE ALERT: ${_titleController.text} - ${_bodyController.text}'
      },
    );
    setState(() {
      _activeTriggers.add({
        'id': mainId, 'subIds': [mainId], 'title': _titleController.text, 'body': _bodyController.text,
        'subtitle': "One-Time: ${scheduledDate.day}/${scheduledDate.month}/${scheduledDate.year} at ${_oneTimeTime.format(context)}",
        'type': 'OneTime', 'nextFireDate': scheduledDate,
      });
      _editingMainId = null;
    });
    await _saveTriggers();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Strike Armed!"), backgroundColor: Colors.green));
  }

  Future<void> _armRepeatingEngine() async {
    if (_scheduleType == 'Weekly' && _selectedDays.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select at least one day!"), backgroundColor: Colors.red)); return; }
    if (_scheduleType == 'Monthly' && _selectedMonths.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select at least one month!"), backgroundColor: Colors.red)); return; }
    if (_editingMainId != null) await _cancelTrigger(_editingMainId!);

    final int mainId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    List<int> subAlarmIds = [];
    String displaySubtitle = "";
    DateTime soonestDate = DateTime.now().add(const Duration(days: 365));

    if (_scheduleType == 'Daily') {
      soonestDate = _nextTime(_repeatTime);
      await _injectRepeating(mainId, soonestDate, DateTimeComponents.time);
      subAlarmIds.add(mainId); displaySubtitle = "Daily at ${_repeatTime.format(context)}";
    } else if (_scheduleType == 'Weekly') {
      for (String day in _selectedDays) {
        int dayIndex = _weekDays.indexOf(day) + 1; int subId = mainId + dayIndex; 
        DateTime d = _nextWeekday(dayIndex, _repeatTime);
        if (d.isBefore(soonestDate)) soonestDate = d;
        await _injectRepeating(subId, d, DateTimeComponents.dayOfWeekAndTime);
        subAlarmIds.add(subId);
      }
      displaySubtitle = "Weekly on ${_selectedDays.join(', ')}";
    } else if (_scheduleType == 'Monthly') {
      int targetDay = int.tryParse(_manualDateController.text) ?? 1;
      for (String month in _selectedMonths) {
        int monthIndex = _months.indexOf(month) + 1; int subId = mainId + monthIndex;
        DateTime d = _nextDate(monthIndex, targetDay, _repeatTime);
        if (d.isBefore(soonestDate)) soonestDate = d;
        await _injectRepeating(subId, d, DateTimeComponents.dateAndTime);
        subAlarmIds.add(subId);
      }
      displaySubtitle = "Monthly on ${_selectedMonths.join(', ')} ($targetDay)";
    } else if (_scheduleType == 'Yearly') {
      soonestDate = _nextDate(_calendarDate.month, _calendarDate.day, _repeatTime);
      await _injectRepeating(mainId, soonestDate, DateTimeComponents.dateAndTime);
      subAlarmIds.add(mainId); displaySubtitle = "Yearly on ${_months[_calendarDate.month - 1]} ${_calendarDate.day}";
    }

    setState(() {
      _activeTriggers.add({ 
        'id': mainId, 'subIds': subAlarmIds, 'title': _titleController.text, 'body': _bodyController.text, 
        'subtitle': displaySubtitle, 'type': _scheduleType, 'nextFireDate': soonestDate,
        'rawTime': _repeatTime, 'rawDays': List<String>.from(_selectedDays), 'rawMonths': List<String>.from(_selectedMonths),
        'rawDate': int.tryParse(_manualDateController.text) ?? 1, 'rawFullDate': _calendarDate,
      });
      _editingMainId = null;
    });
    await _saveTriggers();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Patrol Armed!"), backgroundColor: Colors.green));
  }

  Future<void> _injectRepeating(int id, DateTime date, DateTimeComponents matchLogic) async {
    await flutterLocalNotificationsPlugin.zonedSchedule(
      id: id, title: _titleController.text, body: _bodyController.text, payload: _generatePayload(),
      scheduledDate: tz.TZDateTime.from(date, tz.local), notificationDetails: NotificationDetails(android: _getNotificationDetails()),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle, matchDateTimeComponents: matchLogic,
    );
  }

  DateTime _nextTime(TimeOfDay time) { final now = DateTime.now(); DateTime d = DateTime(now.year, now.month, now.day, time.hour, time.minute); return d.isBefore(now) ? d.add(const Duration(days: 1)) : d; }
  DateTime _nextWeekday(int wDay, TimeOfDay time) { DateTime d = _nextTime(time); while (d.weekday != wDay) { d = d.add(const Duration(days: 1)); } return d; }
  DateTime _nextDate(int m, int d, TimeOfDay time) { final now = DateTime.now(); DateTime date = DateTime(now.year, m, d, time.hour, time.minute); return date.isBefore(now) ? DateTime(now.year + 1, m, d, time.hour, time.minute) : date; }

  // --- UI COMPONENTS ---
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
      DateTime nextFire = trigger['nextFireDate'];
      String sectionHeader = "LATER";
      if (nextFire.isBefore(endOfToday)) {
        sectionHeader = "TODAY";
      } else if (nextFire.isBefore(endOfWeek)) sectionHeader = "THIS WEEK";

      if (sectionHeader != currentHeader) {
        groupedItems.add(Padding(
          padding: const EdgeInsets.only(top: 15, bottom: 5),
          child: Text(sectionHeader, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.5, color: Colors.grey)),
        ));
        currentHeader = sectionHeader;
      }

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
                      Row(
                        children: [
                          Text(trigger['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.green)),
                            child: const Text("ARMED", style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                          )
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(trigger['subtitle'], style: const TextStyle(fontSize: 13)),
                      Text("Payload: ${trigger['body']}", style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)),
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
          Row(
            children: [
              Expanded(child: Card(child: ListTile(title: const Text("Date"), subtitle: Text("${_oneTimeDate.day}/${_oneTimeDate.month}/${_oneTimeDate.year}", style: const TextStyle(fontWeight: FontWeight.bold)), onTap: () async { final p = await showDatePicker(context: context, initialDate: _oneTimeDate, firstDate: DateTime.now(), lastDate: DateTime(2100)); if (p != null) setState(() => _oneTimeDate = p); }))),
              Expanded(child: Card(child: ListTile(title: const Text("Time"), subtitle: Text(_oneTimeTime.format(context), style: const TextStyle(fontWeight: FontWeight.bold)), onTap: () async { final p = await showTimePicker(context: context, initialTime: _oneTimeTime); if (p != null) setState(() => _oneTimeTime = p); }))),
            ],
          ),
          _buildSharedInputs(),
          SizedBox(width: double.infinity, height: 60, child: ElevatedButton.icon(onPressed: _armOneTimeEngine, icon: Icon(_editingMainId != null ? Icons.sync : Icons.bolt), label: Text(_editingMainId != null ? "UPDATE STRIKE" : "ARM STRIKE"), style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white))),
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
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: SegmentedButton<String>(showSelectedIcon: false, segments: const [ButtonSegment(value: 'Daily', label: Text('Daily')), ButtonSegment(value: 'Weekly', label: Text('Weekly')), ButtonSegment(value: 'Monthly', label: Text('Monthly')), ButtonSegment(value: 'Yearly', label: Text('Yearly'))], selected: {_scheduleType}, onSelectionChanged: (Set<String> newSelection) => setState(() => _scheduleType = newSelection.first))),
          const SizedBox(height: 20),
          if (_scheduleType == 'Weekly') Wrap(spacing: 5.0, children: _weekDays.map((day) => FilterChip(label: Text(day), selected: _selectedDays.contains(day), onSelected: (bool selected) => setState(() { selected ? _selectedDays.add(day) : _selectedDays.remove(day); }))).toList()),
          if (_scheduleType == 'Monthly') ...[Wrap(spacing: 5.0, children: _months.map((month) => FilterChip(label: Text(month), selected: _selectedMonths.contains(month), onSelected: (bool selected) => setState(() { selected ? _selectedMonths.add(month) : _selectedMonths.remove(month); }))).toList()), const SizedBox(height: 15), TextField(controller: _manualDateController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Day (1-31)", border: OutlineInputBorder()))],
          if (_scheduleType == 'Yearly') Card(child: ListTile(title: const Text("Pick Annual Date"), subtitle: Text("${_months[_calendarDate.month - 1]} ${_calendarDate.day}", style: const TextStyle(fontWeight: FontWeight.bold)), trailing: IconButton(icon: const Icon(Icons.calendar_month), onPressed: () async { final p = await showDatePicker(context: context, initialDate: _calendarDate, firstDate: DateTime(2000), lastDate: DateTime(2100)); if (p != null) setState(() => _calendarDate = p); }))),
          const SizedBox(height: 10),
          Card(child: ListTile(leading: Icon(Icons.alarm, color: Theme.of(context).colorScheme.primary), title: Text(_repeatTime.format(context), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), trailing: ElevatedButton(onPressed: () async { final p = await showTimePicker(context: context, initialTime: _repeatTime); if (p != null) setState(() => _repeatTime = p); }, child: const Text("SET TIME")))),
          _buildSharedInputs(),
          SizedBox(width: double.infinity, height: 60, child: ElevatedButton.icon(onPressed: _armRepeatingEngine, icon: Icon(_editingMainId != null ? Icons.sync : Icons.loop), label: Text(_editingMainId != null ? "UPDATE PATROL" : "ARM PATROL"), style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white))),
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
        SwitchListTile(title: const Text("Dark Mode (Tactical Theme)"), secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode), value: isDark, onChanged: (val) async { themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light; final prefs = await SharedPreferences.getInstance(); await prefs.setBool('isDark', val); }),
        const Divider(),
        ListTile(title: const Text("Theme Accent Color"), subtitle: Padding(padding: const EdgeInsets.only(top: 10.0), child: Wrap(spacing: 12, children: _themeColors.map((color) => GestureDetector(onTap: () async { colorNotifier.value = color; final prefs = await SharedPreferences.getInstance(); await prefs.setInt('themeColor', color.value); }, child: CircleAvatar(backgroundColor: color, radius: 18, child: colorNotifier.value.value == color.value ? const Icon(Icons.check, color: Colors.white, size: 20) : null))).toList()))),
        const Divider(),
        StatefulBuilder(builder: (context, setLocalState) { return ListTile(title: const Text("UI Text Scale"), subtitle: Slider(value: _localFontScale, min: 0.8, max: 1.5, divisions: 7, label: _localFontScale.toStringAsFixed(1), onChanged: (val) { setLocalState(() => _localFontScale = val); }, onChangeEnd: (val) async { fontScaleNotifier.value = val; final prefs = await SharedPreferences.getInstance(); await prefs.setDouble('fontScale', val); }), leading: const Icon(Icons.format_size)); }),
        const Divider(),
        SwitchListTile(title: const Text("Override Audio Protocol"), subtitle: const Text("Requires custom_alarm.mp3 in raw folder"), secondary: const Icon(Icons.audiotrack), value: _useCustomSound, onChanged: (val) => setState(() => _useCustomSound = val)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("DUKE ALERT", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)), centerTitle: true),
      body: IndexedStack(index: _currentTabIndex, children: [_buildOneTimeTab(), _buildRepeatingTab(), _buildSettingsTab()]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTabIndex,
        onTap: (index) => setState(() => _currentTabIndex = index),
        selectedItemColor: Theme.of(context).colorScheme.primary,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.gps_fixed), label: 'Strike'),
          BottomNavigationBarItem(
            icon: Badge(isLabelVisible: _activeTriggers.isNotEmpty, label: Text('${_activeTriggers.length}'), child: const Icon(Icons.radar)), 
            label: 'Patrol'
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}