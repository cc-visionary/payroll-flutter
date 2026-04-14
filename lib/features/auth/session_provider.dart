import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authStateProvider = StreamProvider<Session?>((ref) {
  final client = Supabase.instance.client;
  return client.auth.onAuthStateChange.map((e) => e.session).startWith(client.auth.currentSession);
});

extension _Start<T> on Stream<T> {
  Stream<T> startWith(T? initial) async* {
    if (initial != null) yield initial;
    yield* this;
  }
}
