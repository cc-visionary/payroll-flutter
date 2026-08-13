import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/breakpoints.dart';
import '../../documents/providers.dart';
import 'kpis_pane.dart';
import 'outcomes_pane.dart';
import 'people_pane.dart';
import 'responsibilities_pane.dart';
import 'role_details_pane.dart';

/// The one place a role is authored: details, responsibilities, desired
/// outcomes, KPIs and the people holding it. Reached from the Roles tab; the
/// role card screen is the read-only artifact this produces.
///
/// [OutcomesPane] sits between responsibilities and KPIs — the cascade this
/// screen authors is responsibility → outcome → KPI, and it renders in that
/// order top to bottom.
///
/// Each pane owns its own save. There is deliberately no single form key
/// spanning them — a manager fixing one responsibility's hours should not be
/// blocked by an unrelated empty field three panes away.
///
/// The panes populate controllers in `initState` with no `didUpdateWidget`
/// resync, so reusing one mounted instance across a `cardId` change would
/// leave it showing the previous card's edited-but-unsaved values. That is
/// not reachable here: every call site reaches this screen via
/// `context.push('/workforce-planning/roles/$id')`, and go_router assigns
/// every pushed page a fresh, globally-unique key regardless of the matched
/// `:id` — so a new `cardId` always means a brand-new `RoleWorkbenchScreen`
/// element, never this one rebuilding in place. `cardId` is therefore fixed
/// for the lifetime of any given instance, and the panes below carry no key
/// of their own.
///
/// That conclusion rests entirely on `push`. Routing here with
/// `context.go`/`context.replace`/`pushReplacement`, or hosting this screen
/// inside a `StatefulShellBranch` (whose branch navigator keeps one page
/// alive across route changes), would all reuse the same element for a new
/// `cardId` and resurface the stale-controller bug — silently, as another
/// role's unsaved edits. Add a `ValueKey(cardId)` on each pane before making
/// any of those changes.
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
              RoleDetailsPane(card: card),
              const SizedBox(height: 16),
              ResponsibilitiesPane(
                cardId: card.id,
                companyId: card.companyId,
              ),
              const SizedBox(height: 16),
              OutcomesPane(cardId: card.id, companyId: card.companyId),
              const SizedBox(height: 16),
              KpisPane(cardId: card.id, companyId: card.companyId),
              const SizedBox(height: 16),
              PeoplePane(cardId: card.id),
            ],
          );
        },
      ),
    );
  }
}
