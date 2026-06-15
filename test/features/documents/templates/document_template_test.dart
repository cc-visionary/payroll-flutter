import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:payroll_flutter/features/documents/blocks/block.dart';
import 'package:payroll_flutter/features/documents/templates/document_template.dart';

class _StubInputs extends TemplateInputs {
  final String name;
  _StubInputs(this.name);
  @override
  Map<String, dynamic> toDebugMap() => {'name': name};
  @override
  Map<String, dynamic> toJson() => {'name': name};
}

class _StubTemplate extends DocumentTemplate<_StubInputs> {
  const _StubTemplate();
  @override
  String get id => 'stub';
  @override
  String get name => 'Stub';
  @override
  String get description => 'A stub';
  @override
  IconData get icon => Icons.description_outlined;
  @override
  int get version => 1;
  @override
  _StubInputs emptyInputs() => _StubInputs('');
  @override
  Future<_StubInputs> autofill(AutofillContext ctx) async => _StubInputs('');
  @override
  List<Gate> gates(AutofillContext ctx) => const [];
  @override
  List<ValidationError> validate(_StubInputs inputs) =>
      inputs.name.isEmpty ? const [ValidationError('name', 'required')] : const [];
  @override
  List<Block> build(_StubInputs inputs) => const [];
}

void main() {
  test('TemplateInputs.toDebugMap returns key/value', () {
    final i = _StubInputs('Donald');
    expect(i.toDebugMap(), {'name': 'Donald'});
  });

  test('Gate carries reason', () {
    const g = Gate('Available only after separation');
    expect(g.reason, 'Available only after separation');
  });

  test('ValidationError carries field + message', () {
    const e = ValidationError('amount', 'must be > 0');
    expect(e.field, 'amount');
    expect(e.message, 'must be > 0');
  });

  test('Stub template validate flags empty name', () {
    const t = _StubTemplate();
    expect(t.validate(_StubInputs('')).length, 1);
    expect(t.validate(_StubInputs('Donald')).length, 0);
  });
}
