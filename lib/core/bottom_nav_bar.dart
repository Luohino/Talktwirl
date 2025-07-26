import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/profile_provider.dart';
import '../core/avatar_widget.dart';
import '../screens/home_screen.dart';
import '../screens/add_post_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/post_screen.dart';
import '../core/supabase_client.dart';

enum BottomNavTab { home, add, profile, none }

class BottomNavBar extends StatelessWidget {
  final BottomNavTab activeTab;
  const BottomNavBar({Key? key, this.activeTab = BottomNavTab.home}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top separator
          Container(
            height: 0.5,
            color: Colors.white12,
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 0, left: 0, right: 0),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.85),
              borderRadius: BorderRadius.circular(0),
          boxShadow: [
            BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                        (route) => false,
                  );
                },
                    child: Container(
                      color: Colors.transparent,
                      alignment: Alignment.center,
                child: _navBarIcon(
                  Icons.home_rounded,
                  isActive: activeTab == BottomNavTab.home ? true : false,
                      ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  if (activeTab != BottomNavTab.add) {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: const Color(0xFF18122B),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                      ),
                      builder: (context) => Padding(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                          top: 16,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                                  leading: const Icon(Icons.image, color: Colors.white),
                              title: const Text('Post (Images)', style: TextStyle(color: Colors.white)),
                              onTap: () async {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AddPostScreen(mediaType: 'image'),
                                  ),
                                );
                              },
                            ),
                            ListTile(
                                  leading: const Icon(Icons.video_library, color: Colors.white),
                              title: const Text('Twirl (Video)', style: TextStyle(color: Colors.white)),
                              onTap: () async {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const PostScreen()),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                },
                    child: Container(
                      color: Colors.transparent,
                      alignment: Alignment.center,
                child: _navBarIcon(
                  Icons.add_box_rounded,
                  isActive: activeTab == BottomNavTab.add ? true : false,
                      ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                      final userId = SupabaseService.client.auth.currentUser?.id ?? '';
                      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => ChangeNotifierProvider(
                            create: (_) => ProfileProvider(userId: userId),
                            child: const ProfileScreen(),
                          ),
                        ),
                        (route) => false,
                      );
                    },
                    child: Container(
                      color: Colors.transparent,
                      alignment: Alignment.center,
                      child: _navBarIcon(
                        null,
                        isActive: activeTab == BottomNavTab.profile ? true : false,
                        isProfile: true,
                        profileWidget: _profileNavBarIcon(context, isActive: activeTab == BottomNavTab.profile ? true : false),
                      ),
                    ),
              ),
            ),
          ],
        ),
          ),
        ],
      ),
    );
  }

  Widget _navBarIcon(
    IconData? icon, {
    required bool isActive,
    bool isProfile = false,
    Widget? profileWidget,
  }) {
    return Center(
      child: isProfile
          ? Icon(
              isActive ? Icons.person : Icons.person_outline,
              color: Colors.white,
              size: 28,
            )
          : Icon(
              icon == Icons.home_rounded
                  ? (isActive ? Icons.home : Icons.home_outlined)
                  : icon,
              color: Colors.white,
              size: 28,
      ),
    );
  }

  Widget _profileNavBarIcon(BuildContext context, {required bool isActive}) {
    final profile = Provider.of<ProfileProvider>(context);
    return CircleAvatar(
      radius: 18,
      backgroundColor: Colors.transparent,
      child: buildUserAvatar(
        profilePhoto: profile.profilePhoto ?? '',
        name: profile.name,
        username: profile.username,
        radius: 18,
        fontSize: 18,
      ),
    );
  }
} 