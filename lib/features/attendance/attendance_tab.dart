import 'package:flutter/material.dart';

import 'attendance_screen.dart';
import 'team_screen.dart';

/// The Attendance tab for a login that has BOTH its own DTR and the team's
/// (an HR employee): a "Mine / Everyone" switch above whichever view is on.
/// Each view keeps its state in its controller, so switching costs nothing.
class AttendanceTab extends StatefulWidget {
  const AttendanceTab({super.key});

  @override
  State<AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<AttendanceTab> {
  bool _team = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Mine'), icon: Icon(Icons.person_outline)),
              ButtonSegment(value: true, label: Text('Everyone'), icon: Icon(Icons.groups_outlined)),
            ],
            selected: {_team},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _team = s.first),
          ),
        ),
        Expanded(child: _team ? const TeamAttendanceScreen() : const AttendanceScreen()),
      ],
    );
  }
}
