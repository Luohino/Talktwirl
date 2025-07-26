import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/profile_provider.dart';
import 'core/supabase_client.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/continue_screen.dart';
import 'screens/auth/new_password_screen.dart';
import 'screens/home_screen.dart'; // For SwipeNavigator and HomeScreen (no MessageScreen)
import 'screens/profile_screen.dart';
import 'screens/search_screen.dart';
import 'screens/notification_screen.dart';
import 'screens/main_screen.dart';
import 'screens/terms_and_conditions_screen.dart';
import 'core/theme.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('profiles');
  await Hive.openBox('messages');
  await SupabaseService.initialize();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(
    ChangeNotifierProvider(
      create: (_) => ProfileProvider(userId: SupabaseService.client.auth.currentUser?.id ?? ''),
      child: MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  bool _isOnline = false;
  final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupConnectivityListener();
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
          // Set online status on sign in
          _setOnlineStatus(true);
        }
      } else if (event == AuthChangeEvent.signedOut) {
        final profileProvider = Provider.of<ProfileProvider>(context, listen: false);
        profileProvider.updateProfile(
          username: '',
          name: '',
          website: '',
          bio: '',
          email: '',
          phone: '',
          gender: '',
          profilePhoto: null,
        );
        setState(() {});
        // Set offline status on sign out
        _setOnlineStatus(false);
      }
    });
  }

  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) async {
      final user = SupabaseService.client.auth.currentUser;
      if (user == null) return;
      final hasConnection = result != ConnectivityResult.none;
      if (hasConnection && !_isOnline) {
        _setOnlineStatus(true);
      } else if (!hasConnection && _isOnline) {
        _setOnlineStatus(false);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    if (state == AppLifecycleState.resumed) {
      _setOnlineStatus(true);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      _setOnlineStatus(false);
    }
  }

  Future<void> _setOnlineStatus(bool online) async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    _isOnline = online;
    await SupabaseService.client.rpc('update_user_online_status', params: {
      'user_id': user.id,
      'is_online': online,
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TalkTwirl',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      initialRoute: SplashScreen.routeName,
      routes: {
        SplashScreen.routeName: (context) => const SplashScreen(),
        LoginScreen.routeName: (context) => const LoginScreen(),
        SignUpScreen.routeName: (context) => const SignUpScreen(),
        ForgotPasswordScreen.routeName: (context) => const ForgotPasswordScreen(),
        ContinueScreen.routeName: (context) => const ContinueScreen(),
        NewPasswordScreen.routeName: (context) => const NewPasswordScreen(),
        '/home': (context) => const HomeScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/search': (context) => const SearchScreen(),
        '/notifications': (context) => const NotificationScreen(),
        '/main': (context) => const MainScreen(),
        '/terms': (context) => const TermsAndConditionsScreen(),
        '/messages': (context) => const HomeScreen(),
      },
      navigatorObservers: [routeObserver],
    );
  }
}
