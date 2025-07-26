import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import '../core/profile_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({Key? key}) : super(key: key);

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _usernameController;
  late TextEditingController _websiteController;
  late TextEditingController _bioController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _genderController;
  File? _profileImage;
  String? _profileImagePath;

  @override
  void initState() {
    super.initState();
    _checkAccountSuspended();
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    _nameController = TextEditingController(text: profile.name);
    _usernameController = TextEditingController(text: profile.username);
    _websiteController = TextEditingController(text: profile.website);
    _bioController = TextEditingController(text: profile.bio);
    _emailController = TextEditingController(text: profile.email);
    _phoneController = TextEditingController(text: profile.phone);
    _genderController = TextEditingController(text: profile.gender);
    _profileImagePath = profile.profilePhoto;
  }

  Future<void> _checkAccountSuspended() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    final doc = await SupabaseService.client.from('profiles').select().eq('id', user.id).maybeSingle();
    if (doc == null) {
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Your account is suspended'),
          content: const Text('Your account has been suspended or deleted.'),
          actions: [
            TextButton(
              onPressed: () async {
                await SupabaseService.client.auth.signOut();
                if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text('Log out'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _profileImage = File(pickedFile.path);
        _profileImagePath = pickedFile.path;
      });
    }
  }

  Future<String?> _getCurrentUserId() async {
    final user = SupabaseService.client.auth.currentUser;
    return user?.id;
  }

  Future<bool> _isUsernameUnique(String username) async {
    final uname = username.trim().toLowerCase();
    final response = await SupabaseService.client
        .from('usernames')
        .select('username')
        .eq('username', uname)
        .maybeSingle();
    return response == null;
  }

  Future<String?> _uploadProfilePhoto(File file, String userId) async {
    final fileExt = file.path.split('.').last;
    final fileName = 'profile_photos/${userId}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    final storage = SupabaseService.client.storage.from('profile-photos');
    final uploadRes = await storage.upload(fileName, file);
    if (uploadRes == null || uploadRes is! String) {
      print('Upload failed');
      return null;
    }
    final publicUrl = storage.getPublicUrl(fileName);
    return publicUrl;
  }

  void _saveProfile() async {
    print('SaveProfile called!');
    print('mounted: $mounted');
    try {
      final profileProvider = Provider.of<ProfileProvider>(context, listen: false);
      final userId = await _getCurrentUserId();
      final newUsername = _usernameController.text.trim();
      String? uploadedPhotoUrl;
      if (userId != null) {
        // If a new profile image was picked, upload it
        if (_profileImage != null) {
          uploadedPhotoUrl = await _uploadProfilePhoto(_profileImage!, userId);
        }
        // Fetch current profile
        final currentProfile = await SupabaseService.client.from('profiles').select().eq('id', userId).maybeSingle();
        if (currentProfile == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not load your profile from the database.'), backgroundColor: Colors.red),
          );
          return;
        }
        final currentUsername = (currentProfile['username'] as String?)?.toLowerCase();
        final newUsernameLower = newUsername.toLowerCase();

        if (newUsernameLower != currentUsername) {
          // Only check uniqueness if username is actually changing
          final existing = await SupabaseService.client
              .from('usernames')
              .select('user_id')
              .eq('username', newUsernameLower)
              .maybeSingle();

          if (existing != null && existing['user_id'] != userId) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('This username is already taken. Please choose another one.'), backgroundColor: Colors.red),
            );
            return;
          }
          // Update usernames table
          await SupabaseService.client.from('usernames').insert({'username': newUsernameLower, 'user_id': userId});
          if (currentUsername != null && currentUsername.isNotEmpty) {
            await SupabaseService.client.from('usernames').delete().eq('username', currentUsername);
          }
        }
        // Prepare updated profile with partial edit logic
        final updatedProfile = {
          'id': userId,
          'username': _usernameController.text.trim().isNotEmpty ? _usernameController.text.trim() : currentProfile['username'],
          'name': _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : currentProfile['name'],
          'website': _websiteController.text.trim().isNotEmpty ? _websiteController.text.trim() : currentProfile['website'],
          'bio': _bioController.text.trim().isNotEmpty ? _bioController.text.trim() : currentProfile['bio'],
          'email': _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : currentProfile['email'],
          'phone': _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : currentProfile['phone'],
          'gender': _genderController.text.trim().isNotEmpty ? _genderController.text.trim() : currentProfile['gender'],
          'profile_photo': uploadedPhotoUrl ?? currentProfile['profile_photo'],
        };
        // Update Supabase profiles table
        final response = await SupabaseService.client.from('profiles').upsert(updatedProfile).select().single();
        print('Upsert response: $response');
        if (response == null || (response['error'] != null && response['error'] is Map && response['error']['message'] != null)) {
          if (!mounted) return;
          final errorMsg = response != null && response['error'] != null && response['error']['message'] != null ? response['error']['message'] : 'Unknown error';
          if (errorMsg.contains('duplicate key value') && errorMsg.contains('usernames_pkey')) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('This username is already taken. Please choose another one.'), backgroundColor: Colors.red),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to update profile: $errorMsg'), backgroundColor: Colors.red),
            );
          }
          return;
        }
        // Update provider with new values
        profileProvider.updateProfile(
          name: updatedProfile['name'],
          username: updatedProfile['username'],
          website: updatedProfile['website'],
          bio: updatedProfile['bio'],
          email: updatedProfile['email'],
          phone: updatedProfile['phone'],
          gender: updatedProfile['gender'],
          profilePhoto: updatedProfile['profile_photo'],
        );
        print('Profile updated, popping screen');
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e, stack) {
      print('Exception in _saveProfile: $e');
      print(stack);
      if (mounted) {
        if (e.toString().contains('SocketException')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: const Text('No internet connection.'),
                backgroundColor: Colors.red,
                action: SnackBarAction(
                  label: 'Retry',
                  textColor: Colors.white,
                  onPressed: () => _saveProfile(),
                )),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Unexpected error: $e'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(60, 40),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis),
        ),
        title: const Text('Edit Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saveProfile,
            child: const Text('Done', style: TextStyle(color: Color(0xFF5B8BFE), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: Colors.grey[900],
                    backgroundImage: _profileImage != null
                        ? FileImage(_profileImage!)
                        : (_profileImagePath != null && _profileImagePath!.isNotEmpty)
                            ? (_profileImagePath!.startsWith('http')
                                ? NetworkImage(_profileImagePath!)
                                : FileImage(File(_profileImagePath!))) as ImageProvider
                            : const AssetImage('assets/Oval.png'),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        padding: const EdgeInsets.all(6),
                        child: const Icon(Icons.edit, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _pickImage,
              child: const Text('Change Profile Photo', style: TextStyle(color: Color(0xFF5B8BFE), fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 18),
            _buildField('Name', _nameController),
            _buildField('Username', _usernameController),
            _buildField('Website', _websiteController),
            _buildField('Bio', _bioController, maxLines: 2),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Private Information', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 10),
            _buildField('Email', _emailController),
            _buildField('Phone', _phoneController),
            _buildField('Gender', _genderController),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF5B8BFE)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF8F5CFF), width: 2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
