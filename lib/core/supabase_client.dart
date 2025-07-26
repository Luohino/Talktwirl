import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static const String supabaseUrl = 'https://owrzeuwyksdlbbfqjuen.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im93cnpldXd5a3NkbGJiZnFqdWVuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDk2MzY2MDAsImV4cCI6MjA2NTIxMjYwMH0.tPVPbXMh181afeqw6O8R4LREMn4W2eeWRbaT2vpfvU4';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
