import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// GLOBAL PERSISTENT STATE
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);
final ValueNotifier<double> fontScaleNotifier = ValueNotifier(1.0);
final ValueNotifier<Color> colorNotifier = ValueNotifier(Colors.orange);

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  debugPrint('Action tapped in background: ${notificationResponse.actionId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // --- NEW: LOAD SAVED SETTINGS ON STARTUP ---
  final prefs = await SharedPreferences.getInstance();
  themeNotifier.value = (prefs.getBool('isDark') ?? true) ? ThemeMode.dark : ThemeMode.light;
  fontScaleNotifier.value = prefs.getDouble('fontScale') ?? 1.0;
  colorNotifier.value = Color(prefs.getInt('themeColor') ?? Colors.orange.value);

  try {
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (e) {
      tz.setLocalLocation(tz.getLocation('Asia/Calcutta'));
    }
  } catch (e) {
    debugPrint("TIMEZONE ERROR: $e");
  }
  runApp(const DukeAlertApp());
}

class DukeAlertApp extends StatelessWidget {
  const DukeAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: colorNotifier,
      builder: (_, Color currentColor, __) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeNotifier,
          builder: (_, ThemeMode currentMode, __) {
            return ValueListenableBuilder<double>(
              valueListenable: fontScaleNotifier,
              builder: (_, double currentScale, __) {
                return MaterialApp(
                  title: 'Duke Alert',
                  debugShowCheckedModeBanner: false,
                  // Dynamic Theme Colors applied here!
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

  final TextEditingController _titleController = TextEditingController(text: "Duke Alert");
  final TextEditingController _bodyController = TextEditingController(text: "System check required!");
  final List<Map<String, dynamic>> _activeTriggers = [];
  
  DateTime _oneTimeDate = DateTime.now();
  TimeOfDay _oneTimeTime = TimeOfDay.now();

  String _scheduleType = 'Daily'; 
  TimeOfDay _repeatTime = TimeOfDay.now();
  DateTime _calendarDate = DateTime.now();
  final TextEditingController _manualDateController = TextEditingController(text: "${DateTime.now().day}");
  final List<String> _weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final List<String> _selectedDays = [];
  final List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final List<String> _selectedMonths = [];

  String _snoozeSelection = '5 Minutes';
  bool _useCustomSound = false;
  
  // Local state to fix slider lag
  double _localFontScale = 1.0; 

  // Palette Options
  final List<Color> _themeColors = [
    Colors.orange, Colors.blue, Colors.green, Colors.red, Colors.blueGrey, Colors.deepPurple
  ];

  @override
  void initState() {
    super.initState();
    _localFontScale = fontScaleNotifier.value;
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(android: androidSettings);

    await flutterLocalNotificationsPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) => debugPrint("Tapped!"),
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    
    final androidPlugin = flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
  }

  // --- CORE ENGINE LOGIC ---
  Future<void> _cancelTrigger(int mainId) async {
    final trigger = _activeTriggers.firstWhere((t) => t['id'] == mainId);
    for (int subId in trigger['subIds']) {
      await flutterLocalNotificationsPlugin.cancel(id: subId);
    }
    setState(() => _activeTriggers.removeWhere((t) => t['id'] == mainId));
  }

  AndroidNotificationDetails _getNotificationDetails() {
    return AndroidNotificationDetails(
      'duke_alert_v7', 'Duke Engine',
      importance: Importance.max, priority: Priority.high,
      sound: _useCustomSound ? const RawResourceAndroidNotificationSound('custom_alarm') : null,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('snooze_action', 'Snooze ($_snoozeSelection)'),
        const AndroidNotificationAction('dismiss_action', 'Dismiss', cancelNotification: true),
      ],
    );
  }

  // ONE-TIME
  Future<void> _armOneTimeEngine() async {
    final now = DateTime.now();
    DateTime scheduledDate = DateTime(_oneTimeDate.year, _oneTimeDate.month, _oneTimeDate.day, _oneTimeTime.hour, _oneTimeTime.minute);
    if (scheduledDate.isBefore(now)) return _showError("Cannot schedule in the past!");

    final int mainId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await flutterLocalNotificationsPlugin.zonedSchedule(
      id: mainId, title: _titleController.text, body: _bodyController.text,
      scheduledDate: tz.TZDateTime.from(scheduledDate, tz.local),
      notificationDetails: NotificationDetails(android: _getNotificationDetails()),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );

    setState(() {
      _activeTriggers.add({
        'id': mainId, 'subIds': [mainId], 'title': _titleController.text, 'body': _bodyController.text,
        'subtitle': "One-Time: ${scheduledDate.day}/${scheduledDate.month}/${scheduledDate.year} at ${_oneTimeTime.format(context)}",
      });
    });
    _showSuccess("Strike Armed!");
  }

  // REPEATING
  Future<void> _armRepeatingEngine() async {
    if (_scheduleType == 'Weekly' && _selectedDays.isEmpty) return _showError("Select at least one day!");
    if (_scheduleType == 'Monthly' && _selectedMonths.isEmpty) return _showError("Select at least one month!");

    final int mainId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    List<int> subAlarmIds = [];
    String displaySubtitle = "";

    if (_scheduleType == 'Daily') {
      await _injectRepeating(mainId, _nextTime(_repeatTime), DateTimeComponents.time);
      subAlarmIds.add(mainId);
      displaySubtitle = "Daily at ${_repeatTime.format(context)}";
    } else if (_scheduleType == 'Weekly') {
      for (String day in _selectedDays) {
        int dayIndex = _weekDays.indexOf(day) + 1; 
        int subId = mainId + dayIndex; 
        await _injectRepeating(subId, _nextWeekday(dayIndex, _repeatTime), DateTimeComponents.dayOfWeekAndTime);
        subAlarmIds.add(subId);
      }
      displaySubtitle = "Weekly on ${_selectedDays.join(', ')}";
    } else if (_scheduleType == 'Monthly') {
      int targetDay = int.tryParse(_manualDateController.text) ?? 1;
      for (String month in _selectedMonths) {
        int monthIndex = _months.indexOf(month) + 1;
        int subId = mainId + monthIndex;
        await _injectRepeating(subId, _nextDate(monthIndex, targetDay, _repeatTime), DateTimeComponents.dateAndTime);
        subAlarmIds.add(subId);
      }
      displaySubtitle = "Monthly on ${_selectedMonths.join(', ')} ($targetDay)";
    } else if (_scheduleType == 'Yearly') {
      await _injectRepeating(mainId, _nextDate(_calendarDate.month, _calendarDate.day, _repeatTime), DateTimeComponents.dateAndTime);
      subAlarmIds.add(mainId);
      displaySubtitle = "Yearly on ${_months[_calendarDate.month - 1]} ${_calendarDate.day}";
    }

    setState(() {
      _activeTriggers.add({
        'id': mainId, 'subIds': subAlarmIds, 'title': _titleController.text, 'body': _bodyController.text, 'subtitle': displaySubtitle,
      });
    });
    _showSuccess("Patrol Armed!");
  }

  Future<void> _injectRepeating(int id, DateTime date, DateTimeComponents matchLogic) async {
    await flutterLocalNotificationsPlugin.zonedSchedule(
      id: id, title: _titleController.text, body: _bodyController.text,
      scheduledDate: tz.TZDateTime.from(date, tz.local),
      notificationDetails: NotificationDetails(android: _getNotificationDetails()),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: matchLogic,
    );
  }

  // Helpers
  DateTime _nextTime(TimeOfDay time) {
    final now = DateTime.now();
    DateTime d = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return d.isBefore(now) ? d.add(const Duration(days: 1)) : d;
  }
  DateTime _nextWeekday(int wDay, TimeOfDay time) {
    DateTime d = _nextTime(time);
    while (d.weekday != wDay) { d = d.add(const Duration(days: 1)); }
    return d;
  }
  DateTime _nextDate(int m, int d, TimeOfDay time) {
    final now = DateTime.now();
    DateTime date = DateTime(now.year, m, d, time.hour, time.minute);
    return date.isBefore(now) ? DateTime(now.year + 1, m, d, time.hour, time.minute) : date;
  }
  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));

  // --- UI TABS ---
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 30),
        Text("SCHEDULED RADAR", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        _activeTriggers.isEmpty 
            ? const Center(child: Text("NO THREATS DETECTED", style: TextStyle(fontStyle: FontStyle.italic)))
            : Column(
                children: _activeTriggers.map((trigger) => Card(
                  child: ListTile(
                    title: Text(trigger['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(trigger['subtitle']),
                        Text("Content: ${trigger['body']}", style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                      ],
                    ),
                    trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () => _cancelTrigger(trigger['id'] as int)),
                  ),
                )).toList(),
              ),
      ],
    );
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
              Expanded(
                child: Card(
                  child: ListTile(
                    title: const Text("Date"), subtitle: Text("${_oneTimeDate.day}/${_oneTimeDate.month}/${_oneTimeDate.year}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () async {
                      final p = await showDatePicker(context: context, initialDate: _oneTimeDate, firstDate: DateTime.now(), lastDate: DateTime(2100));
                      if (p != null) setState(() => _oneTimeDate = p);
                    },
                  ),
                ),
              ),
              Expanded(
                child: Card(
                  child: ListTile(
                    title: const Text("Time"), subtitle: Text(_oneTimeTime.format(context), style: const TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () async {
                      final p = await showTimePicker(context: context, initialTime: _oneTimeTime);
                      if (p != null) setState(() => _oneTimeTime = p);
                    },
                  ),
                ),
              ),
            ],
          ),
          _buildSharedInputs(),
          SizedBox(
            width: double.infinity, height: 60,
            child: ElevatedButton.icon(
              onPressed: _armOneTimeEngine, icon: const Icon(Icons.bolt), label: const Text("ARM STRIKE"),
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
          if (_scheduleType == 'Weekly') Wrap(
            spacing: 5.0,
            children: _weekDays.map((day) => FilterChip(
              label: Text(day), selected: _selectedDays.contains(day),
              onSelected: (bool selected) => setState(() { selected ? _selectedDays.add(day) : _selectedDays.remove(day); }),
            )).toList(),
          ),
          if (_scheduleType == 'Monthly') ...[
            Wrap(
              spacing: 5.0,
              children: _months.map((month) => FilterChip(
                label: Text(month), selected: _selectedMonths.contains(month),
                onSelected: (bool selected) => setState(() { selected ? _selectedMonths.add(month) : _selectedMonths.remove(month); }),
              )).toList(),
            ),
            const SizedBox(height: 15),
            TextField(controller: _manualDateController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Day (1-31)", border: OutlineInputBorder())),
          ],
          if (_scheduleType == 'Yearly') Card(
            child: ListTile(
              title: const Text("Pick Annual Date"),
              subtitle: Text("${_months[_calendarDate.month - 1]} ${_calendarDate.day}", style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: IconButton(icon: const Icon(Icons.calendar_month), onPressed: () async {
                final p = await showDatePicker(context: context, initialDate: _calendarDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                if (p != null) setState(() => _calendarDate = p);
              }),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: Icon(Icons.alarm, color: Theme.of(context).colorScheme.primary),
              title: Text(_repeatTime.format(context), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              trailing: ElevatedButton(onPressed: () async {
                final p = await showTimePicker(context: context, initialTime: _repeatTime);
                if (p != null) setState(() => _repeatTime = p);
              }, child: const Text("SET TIME")),
            ),
          ),
          _buildSharedInputs(),
          SizedBox(
            width: double.infinity, height: 60,
            child: ElevatedButton.icon(
              onPressed: _armRepeatingEngine, icon: const Icon(Icons.loop), label: const Text("ARM PATROL"),
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
        
        // THEME TOGGLE
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

        // NEW COLOR PALETTE SELECTOR
        ListTile(
          title: const Text("Theme Accent Color"),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 10.0),
            child: Wrap(
              spacing: 12,
              children: _themeColors.map((color) => GestureDetector(
                onTap: () async {
                  colorNotifier.value = color; // Updates instantly
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt('themeColor', color.value); // Saves permanently
                },
                child: CircleAvatar(
                  backgroundColor: color,
                  radius: 18,
                  child: colorNotifier.value.value == color.value ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                ),
              )).toList(),
            ),
          ),
        ),
        const Divider(),

        // FIXED SLIDER (Smooth drag, saves on release)
        StatefulBuilder(
          builder: (context, setLocalState) {
            return ListTile(
              title: const Text("UI Text Scale"),
              subtitle: Slider(
                value: _localFontScale,
                min: 0.8, max: 1.5, divisions: 7,
                label: _localFontScale.toStringAsFixed(1),
                onChanged: (val) {
                  setLocalState(() => _localFontScale = val); // Updates slider dot instantly
                },
                onChangeEnd: (val) async {
                  fontScaleNotifier.value = val; // Scales app font when you let go
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setDouble('fontScale', val);
                },
              ),
              leading: const Icon(Icons.format_size),
            );
          }
        ),
        const Divider(),

        SwitchListTile(
          title: const Text("Use Custom Sound File"),
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
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.gps_fixed), label: 'Strike'),
          BottomNavigationBarItem(icon: Icon(Icons.radar), label: 'Patrol'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}