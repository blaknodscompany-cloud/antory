import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:hive_flutter/hive_flutter.dart';

const String kBoxName = 'db';
const String kTasksKey = 'tasks';
const String kLogsKey = 'logs';

class CalendarScreen extends StatefulWidget {
  final DateTime initialSelectedDate;
  final ValueChanged<DateTime> onDateSelected;

  const CalendarScreen({
    super.key,
    required this.initialSelectedDate,
    required this.onDateSelected,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final Box _box = Hive.box(kBoxName);

  late DateTime _focusedDay;
  late DateTime _selectedDay;
  CalendarFormat _format = CalendarFormat.month;

  @override
  void initState() {
    super.initState();
    _selectedDay = _dateOnly(widget.initialSelectedDate);
    _focusedDay = _selectedDay;
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _dateKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  List<String> get _tasks {
    final t = _box.get(kTasksKey) as List?;
    return (t ?? const <String>[]).cast<String>();
  }

  Map<String, dynamic> get _allLogs {
    final logs = _box.get(kLogsKey);
    if (logs is Map) return Map<String, dynamic>.from(logs);
    return <String, dynamic>{};
  }

  double _ratioForDate(DateTime d) {
    final tasks = _tasks;
    if (tasks.isEmpty) return 0;

    final all = _allLogs;
    final key = _dateKey(d);
    final raw = all[key];

    // raw: Map(taskName -> bool)
    final Map<String, bool> day = {};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k is String) day[k] = v == true;
      });
    }

    int done = 0;
    for (final t in tasks) {
      if (day[t] == true) done++;
    }
    return done / tasks.length;
  }

  // 5 kademe renk (0-19, 20-39, 40-59, 60-79, 80-100)
  Color _tierColor(double ratio) {
    if (ratio >= 0.80) return const Color(0xFF1B5E20); // kademe 5 (koyu yeşil)
    if (ratio >= 0.60) return const Color(0xFF2E7D32); // kademe 4
    if (ratio >= 0.40) return const Color(0xFF66BB6A); // kademe 3
    if (ratio >= 0.20) return const Color(0xFFEF6C00); // kademe 2 (turuncu)
    return const Color(0xFFC62828); // kademe 1 (kırmızı)
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Takvim')),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: _format,
            startingDayOfWeek: StartingDayOfWeek.monday,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),

            onFormatChanged: (format) => setState(() => _format = format),

            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = _dateOnly(selectedDay);
                _focusedDay = _dateOnly(focusedDay);
              });
              widget.onDateSelected(_selectedDay);
            },

            onPageChanged: (focusedDay) =>
                setState(() => _focusedDay = _dateOnly(focusedDay)),

            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) {
                final ratio = _ratioForDate(_dateOnly(day));
                final color = _tierColor(ratio);

                return _dayCell(day, color, false);
              },
              todayBuilder: (context, day, focusedDay) {
                final ratio = _ratioForDate(_dateOnly(day));
                final color = _tierColor(ratio);

                // Bugün çerçeve
                return _dayCell(day, color, true);
              },
              selectedBuilder: (context, day, focusedDay) {
                final ratio = _ratioForDate(_dateOnly(day));
                final color = _tierColor(ratio);

                // Seçili gün biraz daha belirgin
                return _dayCell(day, color, true, selected: true);
              },
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _Legend(),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _dayCell(
    DateTime day,
    Color color,
    bool outlined, {
    bool selected = false,
  }) {
    final textColor = Colors.white;
    final borderColor = selected ? Colors.black : Colors.black26;

    return Container(
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        border: outlined
            ? Border.all(color: borderColor, width: selected ? 2 : 1)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        '${day.day}',
        style: TextStyle(
          color: textColor,
          fontWeight: selected ? FontWeight.bold : FontWeight.w600,
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c) => Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            dot(const Color(0xFFC62828)),
            const SizedBox(width: 6),
            const Text('0–19%'),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            dot(const Color(0xFFEF6C00)),
            const SizedBox(width: 6),
            const Text('20–39%'),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            dot(const Color(0xFF66BB6A)),
            const SizedBox(width: 6),
            const Text('40–59%'),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            dot(const Color(0xFF2E7D32)),
            const SizedBox(width: 6),
            const Text('60–79%'),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            dot(const Color(0xFF1B5E20)),
            const SizedBox(width: 6),
            const Text('80–100%'),
          ],
        ),
      ],
    );
  }
}
