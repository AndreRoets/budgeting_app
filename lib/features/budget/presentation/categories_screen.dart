import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../application/budget_provider.dart';
import '../domain/models.dart';
import 'forms.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(budgetProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: AppFab(
        onPressed: () => showCategoryForm(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New category'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Card(
            child: Column(children: [
              for (final c in s.categories)
                ListTile(
                  leading: CategoryAvatar(c),
                  title: Text(c.name),
                  subtitle: Text(c.budget > 0
                      ? 'Budget ${money(c.budget, s.currency)} / month'
                      : 'No spending budget'),
                  trailing: c.id == otherCategoryId
                      ? null
                      : const Icon(Icons.edit_outlined, size: 20),
                  onTap: () => showCategoryForm(context, category: c),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}
