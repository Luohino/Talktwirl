import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_client.dart';

/// Call this after every successful Firebase login to link Supabase session.
Future<void> signInSupabaseWithFirebaseUser() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('No Firebase user');
  final idToken = await user.getIdToken();
  if (idToken == null) throw Exception('No Firebase ID token');

  // Debug print for troubleshooting
  final supabaseUrl = SupabaseService.supabaseUrl;
  print('Sending to Supabase: $supabaseUrl/auth/v1/token?grant_type=id_token');
  print('Headers: \\${{
    'apikey': SupabaseService.supabaseAnonKey,
    'Content-Type': 'application/json',
  }}');
  print('Body: \\${jsonEncode({
    'provider': 'firebase',
    'id_token': idToken,
  })}');

  // Exchange Firebase JWT for Supabase session using REST API
  final response = await http.post(
    Uri.parse('$supabaseUrl/auth/v1/token?grant_type=id_token'),
    headers: {
      'apikey': SupabaseService.supabaseAnonKey,
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'provider': 'firebase',
      'id_token': idToken,
    }),
  );
  if (response.statusCode != 200) {
    throw Exception('Failed to exchange Firebase token for Supabase session: \\${response.body}');
  }
  final data = jsonDecode(response.body);
  final accessToken = data['access_token'];
  final refreshToken = data['refresh_token'];
  if (accessToken == null || refreshToken == null) {
    throw Exception('Invalid Supabase session response: \\${response.body}');
  }
  await Supabase.instance.client.auth.recoverSession(
    jsonEncode({
      'access_token': accessToken,
      'refresh_token': refreshToken,
    }),
  );
  print('Supabase session set for Firebase user: \\${user.uid}');
}
