import 'package:flutter/material.dart';

class StateMessage extends StatelessWidget {
  const StateMessage({
    super.key,
    required this.icon,
    required this.text,
    this.details,
    this.action,
    this.iconColor,
  });

  final IconData icon;
  final String text;
  final String? details;
  final Widget? action;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(text),
        subtitle: details == null ? null : Text(details!),
        trailing: action,
      ),
    );
  }
}
