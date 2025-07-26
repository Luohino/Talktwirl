import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/profile_provider.dart';
import 'user_profile_screen.dart';
import '../core/supabase_client.dart';
import '../core/avatar_widget.dart';
import '../core/bottom_nav_bar.dart';
import 'twirl_screen.dart';
import 'message_screen.dart';
import 'notification_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  bool _profileActive = false;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _userResults = [];
  bool _isLoading = false;
  int _unseenNotificationCount = 0; // New state variable for unseen notifications

  @override
  void initState() {
    super.initState();
    _checkUserSuspended();
    _fetchAllUsers();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkUserSuspended() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    final userDoc = await SupabaseService.client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .single();
    if (userDoc == null) {
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF261531),
            title: const Text('Your account is suspended', style: TextStyle(color: Colors.white)),
            content: const Text('This account is no longer available.', style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () async {
                  await SupabaseService.client.auth.signOut();
                  Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                },
                child: const Text('Log out', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _fetchAllUsers() async {
    setState(() => _isLoading = true);
    try {
      final currentUser = SupabaseService.client.auth.currentUser;
      dynamic response;
      if (currentUser?.id != null) {
        response = await SupabaseService.client
            .from('profiles')
            .select()
            .neq('id', currentUser!.id);
      } else {
        response = await SupabaseService.client
            .from('profiles')
            .select();
      }
      final List<dynamic> data = response;
      setState(() {
        _userResults = data.map((doc) => {
          'username': doc['username'] ?? '',
          'profilePhoto': doc['profile_photo'] != null && doc['profile_photo'].toString().isNotEmpty
              ? doc['profile_photo']
              : 'assets/Oval.png',
          'name': doc['name'] ?? '',
          'uid': doc['id'],
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _userResults = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().contains('SocketException')
              ? 'No internet connection.'
              : 'Failed to load users: ${e.toString()}'),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _fetchAllUsers(),
          ),
        ),
      );
    }
  }

  void _onSearchChanged() async {
    final query = _searchController.text.trim().toLowerCase();
    final currentUser = SupabaseService.client.auth.currentUser;
    if (query.isEmpty) {
      await _fetchAllUsers();
      return;
    }
    setState(() => _isLoading = true);
    try {
      dynamic response;
      if (currentUser?.id != null) {
        response = await SupabaseService.client
            .from('profiles')
            .select()
            .or('username.ilike.%$query%,name.ilike.%$query%')
            .neq('id', currentUser!.id);
      } else {
        response = await SupabaseService.client
            .from('profiles')
            .select()
            .or('username.ilike.%$query%,name.ilike.%$query%');
      }
      final List<dynamic> data = response;
      setState(() {
        _userResults = data.map((doc) => {
          'username': doc['username'] ?? '',
          'profilePhoto': doc['profile_photo'] != null && doc['profile_photo'].toString().isNotEmpty
              ? doc['profile_photo']
              : 'assets/Oval.png',
          'name': doc['name'] ?? '',
          'uid': doc['id'],
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _userResults = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().contains('SocketException')
              ? 'No internet connection.'
              : 'Search failed: ${e.toString()}'),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _onSearchChanged(),
          ),
        ),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen for profile photo changes from ProfileScreen
    final ModalRoute? route = ModalRoute.of(context);
    if (route != null && route.settings.arguments is Map) {
      final args = route.settings.arguments as Map;
      if (args['profilePhoto'] != null) {
        setState(() {
          // _profilePhoto = args['profilePhoto'] as String?;
        });
      }
    }
  }

  @override
  void didPopNext() {
    setState(() {
      _profileActive = false;
    });
  }

  void _onAddPostTap() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18122B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.image, color: Colors.white),
            title: const Text('Post (Image)', style: TextStyle(color: Colors.white)),
            onTap: () async {
              Navigator.pop(context);
              // Use permission_handler and image_picker as in HomeScreen
            },
          ),
          ListTile(
            leading: const Icon(Icons.video_library, color: Colors.white),
            title: const Text('Twirl (Video)', style: TextStyle(color: Colors.white)),
            onTap: () async {
              Navigator.pop(context);
              // Use permission_handler and image_picker as in HomeScreen
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = SupabaseService.client.auth.currentUser;
    // When building the user list, filter out the current user
    final filteredUserResults = _userResults.where((user) => user['uid'] != currentUser?.id).toList();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 26),
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(minWidth: 32),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Image.asset('assets/icon.png', height: 28),
            Expanded(
              child: ShaderMask(
                shaderCallback: (Rect bounds) {
                  return const LinearGradient(
                    colors: [Colors.white, Colors.white],
                  ).createShader(bounds);
                },
                child: const Text(
                  'TalkTwirl',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  maxLines: 1,
                ),
              ),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white24, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.play_circle_outline, color: Color(0xFFFAE6FF), size: 24),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TwirlScreen()),
                    );
                  },
                ),
                const SizedBox(width: 2),
                Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_none, color: Color(0xFFFAE6FF), size: 24),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const NotificationScreen()),
                        );
                      },
                    ),
                    if (_unseenNotificationCount > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 2),
                IconButton(
                  icon: const Icon(Icons.message_outlined, color: Color(0xFFFAE6FF), size: 24),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MessageScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 10, right: 8),
                  child: Icon(Icons.search, color: Colors.white54, size: 24),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                hintText: 'Search...',
                hintStyle: const TextStyle(color: Colors.white54, fontSize: 15),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 0),
              ),
            ),
          ),
          // Suggested Users section (top, horizontal scroll)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Suggested Users',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text(
                    'See All',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 80,
            child: filteredUserResults.isEmpty
                ? const Center(child: Text('No users found.', style: TextStyle(color: Colors.white54)))
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filteredUserResults.length,
                    separatorBuilder: (context, idx) => const SizedBox(width: 16),
                    itemBuilder: (context, idx) {
                      final user = filteredUserResults[idx];
                      return Column(
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => UserProfileScreen(
                                    userData: {
                                      'uid': user['uid'],
                                      'username': user['username'],
                                      'name': user['name'],
                                      'profilePhoto': user['profilePhoto'],
                                    },
                                    isCurrentUser: false,
                                  ),
                                ),
                              );
                            },
                            child: buildUserAvatar(
                              profilePhoto: user['profilePhoto'] ?? '',
                              name: user['name'] ?? '',
                              username: user['username'] ?? '',
                              radius: 28,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user['username'],
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          // Search results list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredUserResults.isEmpty
                    ? const Center(
                        child: Text(
                          'No users found.',
                          style: TextStyle(color: Colors.white54, fontSize: 18),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        itemCount: filteredUserResults.length,
                        itemBuilder: (context, idx) {
                          final user = filteredUserResults[idx];
                          return Card(
                            color: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(color: Colors.white24, width: 1.2),
                            ),
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: buildUserAvatar(
                                profilePhoto: user['profilePhoto'] ?? '',
                                name: user['name'] ?? '',
                                username: user['username'] ?? '',
                                radius: 22,
                                fontSize: 22,
                              ),
                              title: Text(
                                user['username'] ?? 'Unknown',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                (user['name'] == null || user['name'].toString().trim().isEmpty)
                                    ? 'TalkTwirl User'
                                    : user['name'],
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => UserProfileScreen(
                                      userData: {
                                        'uid': user['uid'],
                                        'username': user['username'],
                                        'name': user['name'],
                                        'profilePhoto': user['profilePhoto'],
                                      },
                                      isCurrentUser: false,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: const BottomNavBar(activeTab: BottomNavTab.none),
    );
  }

  Widget _navBarIcon(BuildContext context, IconData icon, {required VoidCallback onTap, bool isActive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF8F5CFF).withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(
          icon,
          color: isActive ? const Color(0xFFFE5B8B) : Colors.white.withOpacity(0.85),
          size: 32,
        ),
      ),
    );
  }

  Widget _profileNavBarIcon({required bool isActive}) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    // Use username's first letter if name is empty or is the fallback
    String displayName = (profile.name != null && profile.name.trim().isNotEmpty && profile.name != "TalkTwirl User")
        ? profile.name
        : (profile.username ?? '');
    return buildUserAvatar(
      profilePhoto: profile.profilePhoto ?? '',
      name: displayName,
      username: profile.username ?? '',
      radius: 18,
      fontSize: 18,
    );
  }
}
