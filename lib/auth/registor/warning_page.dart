import 'package:flutter/material.dart';

class WarningPage extends StatefulWidget {
  const WarningPage({super.key});

  @override
  State<WarningPage> createState() => _WarningPageState();
}

class _WarningPageState extends State<WarningPage> {
  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Text('Warning: Please read the terms and conditions carefully.'),
        SizedBox(height: 20),
        Text('By continuing, you agree to the terms and conditions.'),
      ],
    );
  }
}
