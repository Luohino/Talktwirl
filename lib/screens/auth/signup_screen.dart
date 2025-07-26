import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_client.dart';
import '../home_screen.dart';

class SignUpScreen extends StatefulWidget {
  static const String routeName = '/signup';
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _otpFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _usernameFocus = FocusNode();

  int _step = 0; // 0: email, 1: otp, 2: password, 3: username
  bool _isLoading = false;
  String? _inputError;
  String? _otpError;
  String? _passwordError;
  String? _usernameError;
  String? _authValue;
  String? _accessToken;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _emailFocus.dispose();
    _otpFocus.dispose();
    _passwordFocus.dispose();
    _usernameFocus.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return emailRegex.hasMatch(email);
  }

  Future<void> _sendOtp() async {
    setState(() {
      _inputError = null;
      _isLoading = true;
    });
    final input = _emailController.text.trim();
    if (input.isEmpty) {
      setState(() {
        _inputError = 'Enter email address.';
        _isLoading = false;
      });
      return;
    }
    if (_isValidEmail(input)) {
      try {
        await SupabaseService.client.auth.signInWithOtp(
          email: input,
          shouldCreateUser: true,
        );
        setState(() {
          _authValue = input;
          _step = 1;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OTP sent to your email.')),
        );
        FocusScope.of(context).requestFocus(_otpFocus);
      } catch (e) {
        setState(() {
          _inputError = 'Failed to send OTP: ${e.toString()}';
          _isLoading = false;
        });
      }
    } else {
      setState(() {
        _inputError = 'Invalid email address.';
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyOtp() async {
    setState(() {
      _otpError = null;
      _isLoading = true;
    });
    final otp = _otpController.text.trim();
    if (otp.isEmpty) {
      setState(() {
        _otpError = 'Enter the OTP code.';
        _isLoading = false;
      });
      return;
    }
    try {
      final response = await SupabaseService.client.auth.verifyOTP(
        type: OtpType.email,
        email: _authValue!,
        token: otp,
      );
      if (response.session != null && response.user != null) {
        _accessToken = response.session!.accessToken;
        setState(() {
          _step = 2;
          _isLoading = false;
        });
        FocusScope.of(context).requestFocus(_passwordFocus);
      } else {
        setState(() {
          _otpError = 'Invalid OTP code.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _otpError = 'Failed to verify OTP: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _setPassword() async {
    setState(() {
      _passwordError = null;
      _isLoading = true;
    });
    final password = _passwordController.text.trim();
    if (password.length < 6) {
      setState(() {
        _passwordError = 'Password must be at least 6 characters.';
        _isLoading = false;
      });
      return;
    }
    try {
      final res = await SupabaseService.client.auth.updateUser(
        UserAttributes(password: password),
      );
      if (res.user != null) {
        setState(() {
          _step = 3;
          _isLoading = false;
        });
        FocusScope.of(context).requestFocus(_usernameFocus);
      } else {
        setState(() {
          _passwordError = 'Failed to set password.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _passwordError = 'Failed to set password: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _setUsernameAndFinish() async {
    setState(() {
      _usernameError = null;
      _isLoading = true;
    });
    final username = _usernameController.text.trim();
    if (username.isEmpty || username.length < 3) {
      setState(() {
        _usernameError = 'Username must be at least 3 characters.';
        _isLoading = false;
      });
      return;
    }
    try {
      final user = SupabaseService.client.auth.currentUser;
      if (user == null) {
        setState(() {
          _usernameError = 'User not found.';
          _isLoading = false;
        });
        return;
      }
      final res = await SupabaseService.client.from('profiles').upsert({
        'id': user.id,
        'username': username,
        'email': user.email,
        'created_at': DateTime.now().toIso8601String(),
      }).select().single();
      if (res == null || (res['error'] != null && res['error'] is Map && res['error']['message'] != null)) {
        setState(() {
          _usernameError = 'Failed to save profile: '
              '${res != null && res['error'] != null && res['error']['message'] != null ? res['error']['message'] : 'Unknown error'}';
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _isLoading = false;
      });
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      setState(() {
        _usernameError = 'Failed to save profile: \\${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                if (_step == 0) ...[
                  TextField(
                    controller: _emailController,
                    focusNode: _emailFocus,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: (_) => _sendOtp(),
                    decoration: InputDecoration(
                      hintText: 'Email address',
                      hintStyle: TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (_inputError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(_inputError!, style: const TextStyle(color: Colors.redAccent)),
                    ),
                  const SizedBox(height: 24),
                  // Action buttons (Next, Sign up)
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
                      onPressed: _isLoading ? null : _sendOtp,
                          child: _isLoading
                          ? const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.black))
                              : const Text(
                                  'Next',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ),
                  ),
                ],
                if (_step == 1) ...[
                  TextField(
                    controller: _otpController,
                    focusNode: _otpFocus,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: (_) => _verifyOtp(),
                    decoration: InputDecoration(
                      hintText: 'Enter OTP code',
                      hintStyle: TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (_otpError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(_otpError!, style: const TextStyle(color: Colors.redAccent)),
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
                      onPressed: _isLoading ? null : _verifyOtp,
                          child: _isLoading
                          ? const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.black))
                              : const Text(
                                  'Next',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ),
                  ),
                ],
                if (_step == 2) ...[
                  TextField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: (_) => _setPassword(),
                    decoration: InputDecoration(
                      hintText: 'Create a password',
                      hintStyle: TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (_passwordError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(_passwordError!, style: const TextStyle(color: Colors.redAccent)),
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
                      onPressed: _isLoading ? null : _setPassword,
                          child: _isLoading
                          ? const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.black))
                              : const Text(
                                  'Next',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ),
                  ),
                ],
                if (_step == 3) ...[
                  TextField(
                    controller: _usernameController,
                    focusNode: _usernameFocus,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: (_) => _setUsernameAndFinish(),
                    decoration: InputDecoration(
                      hintText: 'Choose a username',
                      hintStyle: TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (_usernameError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(_usernameError!, style: const TextStyle(color: Colors.redAccent)),
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
                      onPressed: _isLoading ? null : _setUsernameAndFinish,
                          child: _isLoading
                          ? const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.black))
                              : const Text(
                                  'Sign up',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Already have an account? ', style: TextStyle(color: Colors.white70)),
                    GestureDetector(
                      onTap: () {
                        Navigator.pushNamed(context, '/login');
                      },
                      child: const Text('Log in', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
