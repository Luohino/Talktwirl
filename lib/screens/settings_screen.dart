import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'terms_and_conditions_screen.dart';
import 'home_screen.dart';
import '../core/supabase_client.dart';
import '../screens/twirl_screen.dart';
import '../screens/post_detail_screen.dart';
import 'post_detail_list.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<Map<String, dynamic>> savedPosts = [];

  Future<void> _fetchSavedPosts() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    final saved = await SupabaseService.client
      .from('saved_posts')
      .select('post_id, posts(*, profiles(username, profile_photo))')
      .eq('user_id', user.id);
    // Debug print
    print('Fetched saved posts from Supabase:');
    print(saved);
    if (saved is List) {
      for (final s in saved) {
        final post = s['posts'];
        print('Saved post: id=${post?['id']} category=${post?['category']} media_type=${post?['media_type']}');
      }
    }
    setState(() {
      savedPosts = List<Map<String, dynamic>>.from(saved.map((s) => s['posts']));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ListTile(
            leading: const Icon(Icons.bookmark, color: Colors.white),
            title: const Text('Saved Posts', style: TextStyle(color: Colors.white)),
            onTap: () async {
              await _fetchSavedPosts();
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.black,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                ),
                builder: (_) => SizedBox(
                  height: 400,
                  child: savedPosts.isEmpty
                      ? const Center(child: Text('No saved posts', style: TextStyle(color: Colors.white70)))
                      : ListView.builder(
                          itemCount: savedPosts.length,
                          itemBuilder: (context, idx) {
                            final post = savedPosts[idx];
                            final isTwirl = post['category'] == 'Twirl' || post['media_type'] == 'video';
                            return Card(
                              color: const Color(0xFF261531),
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: ListTile(
                                onTap: () {
                                  if (isTwirl) {
                                    // Open TwirlScreen with just this twirl
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => TwirlScreen(
                                          twirls: [post],
                                          initialIndex: 0,
                                        ),
                                      ),
                                    );
                                  } else {
                                    // Open PostDetailList with just this post (from post_detail_screen.dart)
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PostDetailList(
                                          posts: [
                                            {
                                              ...post,
                                              'username': post['profiles']?['username'] ?? '',
                                              'profilePhoto': post['profiles']?['profile_photo'] ?? '',
                                              'name': post['profiles']?['name'] ?? '',
                                            }
                                          ],
                                          initialIndex: 0,
                                        ),
                                      ),
                                    );
                                  }
                                },
                                leading: isTwirl
                                    ? Icon(Icons.play_circle_fill, color: Colors.white, size: 48)
                                    : (post['media_url'] != null && post['media_url'].toString().isNotEmpty
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.network(post['media_url'], width: 48, height: 48, fit: BoxFit.cover),
                                          )
                                        : Icon(Icons.image, size: 48, color: Colors.white54)),
                                title: Text(post['profiles']?['username'] ?? '', style: const TextStyle(color: Colors.white)),
                                subtitle: Text(post['caption'] ?? '', style: const TextStyle(color: Colors.white70)),
                                trailing: isTwirl ? Text('Twirl', style: TextStyle(color: Colors.white)) : null,
                              ),
                            );
                          },
                        ),
                ),
              );
            },
          ),
          const Divider(color: Colors.white24),
       
          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.white),
            title: const Text('About', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TermsAndConditionsScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: Colors.black,
                        title: const Text('Sign Out', style: TextStyle(color: Colors.white)),
                        content: const Text('Are you sure you want to sign out?', style: TextStyle(color: Colors.white70)),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await SupabaseService.client.auth.signOut();
                      if (mounted) {
                        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  child: const Text('Sign Out'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: Colors.black,
                        title: const Text('Delete Account', style: TextStyle(color: Colors.white)),
                        content: const Text('Are you sure you want to delete your account? This cannot be undone.', style: TextStyle(color: Colors.white70)),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      final user = SupabaseService.client.auth.currentUser;
                      if (user == null) return;
                      try {
                        await SupabaseService.client.from('profiles').delete().eq('id', user.id);
                        await SupabaseService.client.auth.signOut();
                        if (mounted) {
                          Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Account deletion failed: \\${e.toString()}')),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  child: const Text('Delete Account'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// If any user, post, or saved logic is present, ensure it uses Supabase (no Firebase/Firestore logic found in initial scan).
