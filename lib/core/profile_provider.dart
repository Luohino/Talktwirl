import 'package:flutter/material.dart';

class ProfileProvider extends ChangeNotifier {
  String userId;
  String name;
  String username;
  String website;
  String bio;
  String email;
  String phone;
  String gender;
  String? profilePhoto;
  int postCount = 0;
  int twirlCount = 0;
  int followers = 0;
  int following = 0;

  ProfileProvider({
    required this.userId,
    this.name = 'Ani',
    this.username = 'Luohino',
    this.website = 'Website',
    this.bio = 'This app is designed by Luohino',
    this.email = 'aniketsingh821305@gmail.com',
    this.phone = '+91 91.....46',
    this.gender = 'Male',
    this.profilePhoto,
  });

  void updateProfile({
    String? name,
    String? username,
    String? website,
    String? bio,
    String? email,
    String? phone,
    String? gender,
    String? profilePhoto,
  }) {
    if (name != null) this.name = name;
    if (username != null) this.username = username;
    if (website != null) this.website = website;
    if (bio != null) this.bio = bio;
    if (email != null) this.email = email;
    if (phone != null) this.phone = phone;
    if (gender != null) this.gender = gender;
    if (profilePhoto != null) this.profilePhoto = profilePhoto;
    notifyListeners();
  }

  void incrementPostCount(String category) {
    if (category == 'Post') {
      postCount++;
    } else if (category == 'Twirl') {
      twirlCount++;
    }
    notifyListeners();
  }
}
