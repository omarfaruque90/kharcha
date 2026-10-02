import 'package:flutter/material.dart';

import '../utils/formatters.dart';

/// Small stat card used on the home dashboard.
class SummaryCard extends StatelessWidget {
  final String title;
  final double amount;
  final IconData icon;

  const SummaryCard({
    super.key,
    required this.title,
    required this.amount,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 20),
            const SizedBox(height: 8),
            Text(title, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              formatMoney(amount),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
