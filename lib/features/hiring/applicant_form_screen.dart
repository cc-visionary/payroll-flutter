import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/profile_provider.dart';
import '../../data/models/applicant.dart';
import '../../data/repositories/applicant_repository.dart';

class ApplicantFormScreen extends ConsumerStatefulWidget {
  /// null = create. Non-null = edit existing applicant.
  final String? applicantId;
  const ApplicantFormScreen({super.key, this.applicantId});

  @override
  ConsumerState<ApplicantFormScreen> createState() => _ApplicantFormScreenState();
}

class _ApplicantFormScreenState extends ConsumerState<ApplicantFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;
  Applicant? _seed;

  // Field controllers/state populated in Task 14.
  // (Identity, Role, Sourcing, Offer, Notes sections land in Task 14 and Task 15.)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.applicantId == null) {
      setState(() => _loading = false);
      return;
    }
    final a = await ref.read(applicantRepositoryProvider).byId(widget.applicantId!);
    setState(() {
      _seed = a;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    if (!(profile?.isHrOrAdmin ?? false)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Applicant')),
        body: const Center(child: Text('You do not have permission.')),
      );
    }
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Applicant')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.applicantId == null ? 'New applicant' : 'Edit applicant'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/hiring'),
        ),
      ),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Form sections land in Task 14 and Task 15.')),
      ),
    );
  }
}
