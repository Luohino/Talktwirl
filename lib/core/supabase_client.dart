import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class SupabaseService {
  static const String supabaseUrl = 'https://owrzeuwyksdlbbfqjuen.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im93cnpldXd5a3NkbGJiZnFqdWVuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDk2MzY2MDAsImV4cCI6MjA2NTIxMjYwMH0.tPVPbXMh181afeqw6O8R4LREMn4W2eeWRbaT2vpfvU4';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        detectSessionInUri: true,
        autoRefreshToken: true,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: kDebugMode ? RealtimeLogLevel.info : RealtimeLogLevel.error,
      ),
      storageOptions: const StorageClientOptions(
        retryAttempts: 3,
      ),
      postgrestOptions: const PostgrestClientOptions(
        schema: 'public',
      ),
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  /// Check if user is authenticated and session is valid
  static bool get isAuthenticated {
    final session = client.auth.currentSession;
    return session != null && 
           session.user != null && 
           !session.isExpired;
  }

  /// Refresh session if needed
  static Future<bool> ensureAuthenticated() async {
    try {
      final session = client.auth.currentSession;
      if (session == null) return false;
      
      if (session.isExpired) {
        final response = await client.auth.refreshSession();
        return response.session != null;
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error ensuring authentication: $e');
      }
      return false;
    }
  }

  /// Sign out and clear all cached data
  static Future<void> signOut() async {
    try {
      await client.auth.signOut();
    } catch (e) {
      if (kDebugMode) {
        print('Error signing out: $e');
      }
    }
  }
}
