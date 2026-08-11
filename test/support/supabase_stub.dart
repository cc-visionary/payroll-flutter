import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// In-memory stand-in for the PKCE store, which otherwise reaches for the
/// shared_preferences platform channel that no test binding provides.
class _MemoryStorage extends GotrueAsyncStorage {
  final _items = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _items[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _items[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);
}

/// Initialises Supabase so a screen that calls `Supabase.instance.client`
/// directly can be pumped in a widget test. Call once from `setUpAll`.
///
/// Every query answers with an empty result set: these tests exercise widget
/// behaviour, not data. Override the Riverpod providers for anything the test
/// needs populated.
///
/// Each argument here fixes a specific failure, so do not trim them:
///  * `request: request` — postgrest's _parseResponse dereferences
///    `response.request!`, so a response built without it throws a null-check
///    error on the first query.
///  * `autoRefreshToken: false` — the GoTrue refresh timer outlives the widget
///    and trips flutter_test's "Timer still pending" invariant.
///  * `pkceAsyncStorage` — the default reaches shared_preferences and throws
///    MissingPluginException.
///  * `detectSessionInUri: false` — the deep-link observer needs the app_links
///    platform channel.
Future<void> initSupabaseStub() async {
  await Supabase.initialize(
    url: 'https://stub.supabase.co',
    anonKey: 'stub-anon-key',
    httpClient: MockClient(
      (request) async => http.Response('[]', 200, request: request),
    ),
    authOptions: FlutterAuthClientOptions(
      autoRefreshToken: false,
      localStorage: const EmptyLocalStorage(),
      pkceAsyncStorage: _MemoryStorage(),
      detectSessionInUri: false,
    ),
  );
}
