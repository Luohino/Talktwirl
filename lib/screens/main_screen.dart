import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/profile_provider.dart';
import '../core/bottom_nav_bar.dart';

class MainScreen extends StatelessWidget {
  static const String routeName = '/main';
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profilePhoto = Provider.of<ProfileProvider>(context).profilePhoto;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: Container(
          padding: const EdgeInsets.only(top: 32, left: 0, right: 16),
          color: Colors.black,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 8),
              Stack(
                alignment: Alignment.center,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundImage: profilePhoto != null
                      ? FileImage(File(profilePhoto))
                      : const AssetImage('assets/Oval.png') as ImageProvider,
                  ),
                  Positioned(
                    left: 0,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 22),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'joshua_l',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '11 messages',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              // Removed call and video call icons
            ],
          ),
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        child: Column(
          children: [
            Expanded(
              child: Container(
                color: Colors.transparent,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: List.generate(20, (index) =>
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(child: Text('Message $index', style: TextStyle(color: Colors.white))),
                        const SizedBox(width: 6),
                        Consumer<ProfileProvider>(
                          builder: (context, profile, _) => CircleAvatar(
                            radius: 16,
                            backgroundImage: profile.profilePhoto != null
                              ? FileImage(File(profile.profilePhoto!))
                              : const AssetImage('assets/Oval.png') as ImageProvider,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const SafeArea(child: BottomNavBar(activeTab: BottomNavTab.home)),
    );
  }
}
