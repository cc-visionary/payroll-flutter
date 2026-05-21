import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

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
