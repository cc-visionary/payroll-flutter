import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../../data/models/hiring_entity.dart';

/// Picks the brand logo asset for a hiring entity (by name/code) and loads
/// its bytes. GameCove entities get the GameCove logo; everything else
/// falls back to the Luxium logo. Returns null if the asset can't be
/// loaded (e.g. in a unit-test environment with no asset bundle).
Future<Uint8List?> loadBrandLogoBytes({String? companyName, String? code}) async {
  final n = (companyName ?? '').toLowerCase();
  final c = (code ?? '').toLowerCase();
  final isGameCove = n.contains('gamecove') || n.contains('game cove') ||
      c.contains('gc');
  final asset =
      isGameCove ? 'assets/GameCove Logo.png' : 'assets/Luxium Logo.png';
  try {
    final data = await rootBundle.load(asset);
    return data.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// Resolve the logo bytes for a hiring entity: its uploaded base64 logo if set,
/// otherwise the bundled brand asset via [loadBrandLogoBytes]. Returns null when
/// neither is available (e.g. test env with no asset bundle).
Future<Uint8List?> loadCompanyLogoBytes(HiringEntity? entity) async {
  final b64 = entity?.logoBase64;
  if (b64 != null && b64.isNotEmpty) {
    try {
      return base64.decode(b64);
    } catch (_) {
      // fall through to bundled asset
    }
  }
  return loadBrandLogoBytes(companyName: entity?.name, code: entity?.code);
}
