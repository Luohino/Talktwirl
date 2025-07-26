import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../terms_and_conditions_screen.dart';
import '../../core/supabase_client.dart';

class ForgotPasswordScreen extends StatefulWidget {
  static const String routeName = '/forgot';
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _emailController = TextEditingController();
  bool _agreed = false;
  bool _loading = false;
  bool _isLinkSent = false;
  String? _emailError;
  String? _successMessage;

  void _showTermsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF261531),
        title: const Text('Agreement Required', style: TextStyle(color: Colors.white)),
        content: const Text('You must agree to the terms to continue', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _sendResetEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() { _emailError = 'Please enter your email.'; });
      return;
    }
    if (!_isValidEmail(email)) {
      setState(() { _emailError = 'Please enter a valid email address.'; });
      return;
    }
    if (!_agreed) {
      _showTermsDialog();
      return;
    }
    setState(() { _loading = true; _emailError = null; _successMessage = null; });
    try {
      await SupabaseService.client.auth.resetPasswordForEmail(email);
      setState(() {
        _isLinkSent = true;
        _successMessage = 'Password reset link sent to $email. Please check your inbox.';
      });
    } on AuthException catch (e) {
      setState(() { _emailError = e.message ?? 'Failed to send reset email.'; });
    } catch (e) {
      setState(() { _emailError = 'An error occurred. Please try again.'; });
    }
    setState(() { _loading = false; });
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return emailRegex.hasMatch(email);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.white, Colors.white],
                  ).createShader(bounds),
                  child: const Text(
                    'Talktwirl',
                    style: TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  readOnly: _isLinkSent,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Email address',
                    hintStyle: TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    errorText: _emailError,
                  ),
                  onChanged: (_) {
                    if (_emailError != null) setState(() => _emailError = null);
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    onPressed: _loading || _isLinkSent || !_agreed || !_isValidEmail(_emailController.text.trim())
                        ? null
                        : _sendResetEmail,
                        child: _loading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                              )
                        : Text(
                                'Send Reset Link',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: (_loading || _isLinkSent || !_agreed || !_isValidEmail(_emailController.text.trim()))
                                  ? Colors.grey
                                  : Colors.black,
                      ),
                    ),
                  ),
                ),
                if (_successMessage != null) ...[
                  const SizedBox(height: 18),
                  Text(
                    _successMessage!,
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Checkbox(
                      value: _agreed,
                      onChanged: _isLinkSent
                          ? null
                          : (val) => setState(() => _agreed = val ?? false),
                      activeColor: Colors.white,
                      checkColor: Colors.white,
                    ),
                    Expanded(
                      child: Wrap(
                        children: [
                          const Text('I agree to the ', style: TextStyle(color: Colors.white70)),
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const TermsAndConditionsScreen()),
                            ),
                            child: const Text('Terms & Conditions', style: TextStyle(color: Colors.white, decoration: TextDecoration.underline)),
                          ),
                          const Text(' and ', style: TextStyle(color: Colors.white70)),
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const TermsAndConditionsScreen()),
                            ),
                            child: const Text('Community Guidelines', style: TextStyle(color: Colors.white, decoration: TextDecoration.underline)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('Reminder: You must agree to the terms to use this app.', style: TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 18),
                if (_isLinkSent) ...[
                  const Text(
                    'After clicking the reset link in your email, you will be redirected back to the app to set a new password.',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  // TODO: Handle deep link for password reset in your app (see Supabase docs)
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}



