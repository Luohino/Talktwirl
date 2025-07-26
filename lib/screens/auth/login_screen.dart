import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../terms_and_conditions_screen.dart';
import '../../core/supabase_client.dart';
import 'package:provider/provider.dart';
import '../../core/profile_provider.dart';

class LoginScreen extends StatefulWidget {
  static const String routeName = '/login';
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  bool _isPasswordVisible = false;
  bool _agreed = false;
  String? _loginError;
  bool _isLoading = false;

  Future<void> _loginWithEmail() async {
    setState(() { _isLoading = true; _loginError = null; });
    try {
      String input = _emailController.text.trim();
      final password = _passwordController.text.trim();
      String emailToUse = input;
      // If input does not look like an email, treat as username
      if (!input.contains('@')) {
        final profile = await SupabaseService.client
            .from('profiles')
            .select('email')
            .ilike('username', input)
            .maybeSingle();
        if (profile == null || profile['email'] == null) {
          setState(() { _isLoading = false; _loginError = 'No account found for this username.'; });
          return;
        }
        emailToUse = profile['email'];
      }
      final response = await SupabaseService.client.auth.signInWithPassword(
        email: emailToUse,
        password: password,
      );
      if (response.user == null) {
        setState(() { _isLoading = false; _loginError = 'Invalid credentials.'; });
        return;
      }
      setState(() { _isLoading = false; });
      Navigator.pushReplacementNamed(context, '/home');
    } on AuthException catch (e) {
      String friendlyMessage = e.message;
      if (friendlyMessage.toLowerCase().contains('invalid login credentials') ||
          friendlyMessage.toLowerCase().contains('invalid credentials') ||
          friendlyMessage.toLowerCase().contains('wrong password') ||
          friendlyMessage.toLowerCase().contains('incorrect password')) {
        friendlyMessage = 'Wrong password. Please try again.';
      } else if (friendlyMessage.toLowerCase().contains('user not found') ||
                 friendlyMessage.toLowerCase().contains('no user')) {
        friendlyMessage = 'No account found with this email or username.';
      }
      setState(() { _isLoading = false; _loginError = friendlyMessage; });
    } catch (e) {
      setState(() { _isLoading = false; _loginError = 'Login failed.'; });
    }
  }

  bool get _canLogin =>
    _agreed &&
    _emailController.text.trim().isNotEmpty &&
    _passwordController.text.trim().isNotEmpty &&
    !_isLoading;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(() => setState(() {}));
    _passwordController.addListener(() => setState(() {}));
    // Listen for auth state changes and update profile after login
    SupabaseService.client.auth.onAuthStateChange.listen((data) async {
      final event = data.event;
      final session = data.session;
      if (event == AuthChangeEvent.signedIn && session != null) {
        final user = session.user;
        if (user != null) {
          final profileRes = await SupabaseService.client
              .from('profiles')
              .select()
              .eq('id', user.id)
              .maybeSingle();
          if (profileRes != null && mounted) {
            final profileProvider = Provider.of<ProfileProvider>(context, listen: false);
            profileProvider.updateProfile(
              username: profileRes['username'] ?? '',
              name: profileRes['name'] ?? 'TalkTwirl User',
              website: profileRes['website'] ?? '',
              bio: profileRes['bio'] ?? '',
              email: profileRes['email'] ?? '',
              phone: profileRes['phone'] ?? '',
              gender: profileRes['gender'] ?? '',
              profilePhoto: profileRes['profile_photo'],
            );
            setState(() {});
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _showTermsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 32),
                // Talktwirl title
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
                // Email field (no eye icon)
                TextField(
                  controller: _emailController,
                  focusNode: _emailFocus,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(color: Colors.white),
                  onSubmitted: (_) {
                    FocusScope.of(context).requestFocus(_passwordFocus);
                  },
                  decoration: InputDecoration(
                    hintText: 'Email address or username',
                    hintStyle: TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Password field (with eye icon)
                TextField(
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  obscureText: !_isPasswordVisible,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Enter password',
                    hintStyle: TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility, color: Colors.white),
                      onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                    ),
                  ),
                ),
                if (_loginError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(_loginError!, style: const TextStyle(color: Colors.redAccent)),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Checkbox(
                      value: _agreed,
                      onChanged: (val) => setState(() => _agreed = val ?? false),
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
                const SizedBox(height: 24),
                // Log in button
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
                    onPressed: _canLogin
                        ? () {
                            _loginWithEmail();
                          }
                        : null,
                        child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                            : const Text(
                                'Log in',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: const [
                    Expanded(child: Divider(color: Colors.white24)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text('OR', style: TextStyle(color: Colors.white54)),
                    ),
                    Expanded(child: Divider(color: Colors.white24)),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/forgot');
                    },
                    child: const Text('forgot password?', style: TextStyle(color: Colors.white70)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Don't have an account? ", style: TextStyle(color: Colors.white70)),
                    GestureDetector(
                      onTap: () {
                        Navigator.pushNamed(context, '/signup');
                      },
                      child: const Text('Sign up', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
