import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  await Firebase.initializeApp();
  final firestore = FirebaseFirestore.instance;
  final users = await firestore.collection('users').get();
  for (final doc in users.docs) {
    final data = doc.data();
    int followers = (data['followers'] ?? 0) is int ? data['followers'] : 0;
    int following = (data['following'] ?? 0) is int ? data['following'] : 0;
    if (followers < 0 || following < 0) {
      await firestore.collection('users').doc(doc.id).update({
        'followers': followers < 0 ? 0 : followers,
        'following': following < 0 ? 0 : following,
      });
      print('Fixed negative for user: ${doc.id}');
    }
  }
  print('All negative followers/following counts fixed.');
}
