import 'package:flutter/material.dart';

class PlaceholderScreen extends StatelessWidget {
  final String title;
  final String description;
  const PlaceholderScreen({super.key, required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(description, style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
