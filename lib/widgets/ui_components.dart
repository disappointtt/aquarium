import 'package:flutter/material.dart';

import '../models/history_models.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.titleStyle,
  });

  final String title;
  final Widget? trailing;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: titleStyle ?? theme.textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

class HistoryItemTile extends StatelessWidget {
  const HistoryItemTile({
    super.key,
    required this.event,
    required this.subtitle,
  });

  final HistoryEvent event;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = event.ok ? Colors.green : Colors.red;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withOpacity(0.12),
        child: Icon(
          event.icon,
          color: color,
          size: 18,
        ),
      ),
      title: Text(
        event.title,
        style: Theme.of(context).textTheme.bodyMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        event.ok ? 'OK' : 'Fail',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
