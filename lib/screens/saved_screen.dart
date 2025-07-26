import 'package:flutter/material.dart';
import 'twirl_screen.dart';
import '../core/supabase_client.dart';

class SavedScreen extends StatelessWidget {
  final List<TwirlPost> savedTwirlList;
  const SavedScreen({Key? key, required this.savedTwirlList}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Saved Twirls', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: savedTwirlList.isEmpty
          ? const Center(child: Text('No saved twirls', style: TextStyle(color: Colors.white54)))
          : ListView.builder(
              itemCount: savedTwirlList.length,
              itemBuilder: (context, idx) {
                final post = savedTwirlList[idx];
                return Card(
                  color: const Color(0xFF18122B),
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: ListTile(
                    leading: CircleAvatar(backgroundImage: AssetImage(post.userPfp)),
                    title: Text(post.username, style: const TextStyle(color: Colors.white)),
                    subtitle: Text(post.caption, style: const TextStyle(color: Colors.white70)),
                    trailing: Icon(Icons.play_circle_fill, color: Colors.white),
                  ),
                );
              },
            ),
    );
  }
}
