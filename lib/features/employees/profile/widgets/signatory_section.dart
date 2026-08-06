import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/pdf/signature_png.dart';
import '../../../../data/models/employee.dart';
import '../../../../data/repositories/employee_repository.dart';

/// "Authorized Signatory" card on the employee profile. HR/Admin only
/// (caller gates visibility). Lets HR flag the employee as the company's
/// HR / Legal signatory, set the printed title, and upload a transparent
/// PNG signature that is rendered onto generated documents.
class SignatorySection extends ConsumerStatefulWidget {
  final Employee employee;
  const SignatorySection({super.key, required this.employee});

  @override
  ConsumerState<SignatorySection> createState() => _SignatorySectionState();
}

class _SignatorySectionState extends ConsumerState<SignatorySection> {
  late final TextEditingController _title = TextEditingController(
    text: widget.employee.signatoryTitle ?? '',
  );
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(employeeByIdProvider(widget.employee.id));
    ref.invalidate(hrSignatoryProvider);
    ref.invalidate(legalSignatoryProvider);
  }

  Future<void> _run(Future<void> Function() op) async {
    setState(() => _busy = true);
    try {
      await op();
      if (mounted) _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleCapacity({required bool hr, required bool enable}) async {
    final repo = ref.read(employeeRepositoryProvider);
    if (enable) {
      // Transfer confirm when someone else already holds the capacity.
      Employee? holder;
      try {
        holder = await repo.signatoryFor(hr: hr);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
        return;
      }
      final transferHolder = holder;
      if (transferHolder != null && transferHolder.id != widget.employee.id) {
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Transfer ${hr ? 'HR' : 'Legal'} Signatory?'),
            content: Text(
              '${transferHolder.fullName} currently holds this capacity. Transfer '
              'it to ${widget.employee.fullName}? New documents will carry '
              'the new signatory; already-generated documents keep the '
              'signature they were issued with.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Transfer'),
              ),
            ],
          ),
        );
        if (ok != true) return;
      }
    }
    await _run(
      () => repo.setSignatoryCapacity(
        employeeId: widget.employee.id,
        hr: hr,
        enabled: enable,
      ),
    );
  }

  Future<void> _uploadSignature() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    final bytes = file?.bytes;
    if (bytes == null) return;
    // PNG magic bytes — reject renamed JPEGs etc.; docs need transparency.
    const magic = [0x89, 0x50, 0x4E, 0x47];
    if (bytes.length < 4 ||
        bytes[0] != magic[0] ||
        bytes[1] != magic[1] ||
        bytes[2] != magic[2] ||
        bytes[3] != magic[3]) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Not a PNG file. Upload a transparent PNG.'),
          ),
        );
      }
      return;
    }
    if (bytes.length > 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Signature PNG must be 1 MB or smaller.'),
          ),
        );
      }
      return;
    }
    await _run(
      () => ref
          .read(employeeRepositoryProvider)
          .setSignaturePng(widget.employee.id, base64Encode(bytes)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch the fresh row so toggles reflect writes without a manual reload.
    final emp =
        ref.watch(employeeByIdProvider(widget.employee.id)).asData?.value ??
        widget.employee;
    final sigBytes = decodeSignaturePngB64(emp.signaturePngB64);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Signature & Signing Authority',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'The signature below signs documents this employee is a party to — '
            'such as their penalty repayment agreement. The capacities also put '
            'it on documents they sign on the company\'s behalf.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('HR Signatory'),
            subtitle: const Text('Payslips, COE, NTE, notices, final pay'),
            value: emp.isHrSignatory,
            onChanged: _busy
                ? null
                : (v) => _toggleCapacity(hr: true, enable: v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Legal Signatory'),
            subtitle: const Text('Employment contracts, NDA'),
            value: emp.isLegalSignatory,
            onChanged: _busy
                ? null
                : (v) => _toggleCapacity(hr: false, enable: v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Printed Title',
              hintText: 'e.g. HR Manager',
              isDense: true,
            ),
            onSubmitted: (_) => _saveTitle(),
            onTapOutside: (_) => _saveTitle(),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 160,
                height: 64,
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(6),
                ),
                clipBehavior: Clip.antiAlias,
                child: sigBytes != null
                    ? Image.memory(sigBytes, fit: BoxFit.contain)
                    : Center(
                        child: Text(
                          'No signature',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).disabledColor,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton.tonal(
                    onPressed: _busy ? null : _uploadSignature,
                    child: const Text('Upload PNG'),
                  ),
                  if (sigBytes != null)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => ref
                                  .read(employeeRepositoryProvider)
                                  .setSignaturePng(widget.employee.id, null),
                            ),
                      child: const Text('Remove'),
                    ),
                  Text(
                    'Transparent PNG, max 1 MB.\n'
                    'Leave empty to print a blank line for wet signing.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveTitle() async {
    if (_busy) return;
    final current =
        ref
            .read(employeeByIdProvider(widget.employee.id))
            .asData
            ?.value
            ?.signatoryTitle ??
        widget.employee.signatoryTitle ??
        '';
    if (_title.text.trim() == current.trim()) return;
    await _run(
      () => ref
          .read(employeeRepositoryProvider)
          .setSignatoryTitle(widget.employee.id, _title.text),
    );
  }
}
