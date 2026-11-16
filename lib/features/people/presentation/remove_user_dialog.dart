import 'package:flutter/material.dart';

Future<bool> confirmUserRemoval(BuildContext context, String name) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permanently delete user?'),
        content: Text(
          'Permanently delete $name, their login account, and their associated records and uploaded files? Their email can be registered again. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.person_remove_outlined),
            label: const Text('Delete permanently'),
          ),
        ],
      ),
    ) ??
    false;
