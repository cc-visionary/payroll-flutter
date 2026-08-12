import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/breakpoints.dart';
import '../../documents/providers.dart';
import 'kpis_pane.dart';
import 'people_pane.dart';
import 'responsibilities_pane.dart';
import 'role_details_pane.dart';

/// The one place a role is authored: details, responsibilities, KPIs and the
/// people holding it. Reached from the Roles tab; the Responsibility Card
/// screen is the read-only artifact this produces.
///
/// Each pane owns its own save. There is deliberately no single form key
/// spanning them — a manager fixing one responsibility's hours should not be
/// blocked by an unrelated empty field three panes away.
class RoleWorkbenchScreen extends ConsumerWidget {
  const RoleWorkbenchScreen({super.key, required this.cardId});

  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardAsync = ref.watch(roleScorecardByIdProvider(cardId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Role'),
        actions: [
          IconButton(
            tooltip: 'View card',
            icon: const Icon(Icons.description_outlined),
            onPressed: () => context.push('/responsibility-cards/$cardId'),
          ),
          IconButton(
            tooltip: 'PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => context.push('/responsibility-cards/$cardId/pdf'),
          ),
        ],
      ),
      body: cardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load this role: $e')),
        data: (card) {
          if (card == null) {
            return const Center(child: Text('This role card was not found.'));
          }
          return ListView(
            padding: EdgeInsets.all(isMobile(context) ? 16 : 24),
            children: [
              Text(
                card.jobTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Version ${card.version}'
                '${card.isActive ? '' : ' · inactive'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              RoleDetailsPane(key: ValueKey(cardId), card: card),
              const SizedBox(height: 16),
              ResponsibilitiesPane(
                key: ValueKey(cardId),
                cardId: card.id,
                companyId: card.companyId,
              ),
              const SizedBox(height: 16),
              KpisPane(
                key: ValueKey(cardId),
                cardId: card.id,
                companyId: card.companyId,
              ),
              const SizedBox(height: 16),
              PeoplePane(key: ValueKey(cardId), cardId: card.id),
            ],
          );
        },
      ),
    );
  }
}
