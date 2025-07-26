import 'package:cloud_firestore/cloud_firestore.dart';

/// Run this script with `dart run tool/reset_follow_counts.dart`
/// It will set followers and following to 0 for all users in Firestore.
Future<void> main() async {
  final firestore = FirebaseFirestore.instance;
  final users = await firestore.collection('users').get();
  for (final doc in users.docs) {
    await firestore.collection('users').doc(doc.id).update({
      'followers': 0,
      'following': 0,
    });
    // Optionally, clear the subcollections:
    final followersCol = firestore.collection('users').doc(doc.id).collection('followers');
    final followingCol = firestore.collection('users').doc(doc.id).collection('following');
    final followers = await followersCol.get();
    for (final f in followers.docs) {
      await followersCol.doc(f.id).delete();
    }
    final following = await followingCol.get();
    for (final f in following.docs) {
      await followingCol.doc(f.id).delete();
    }
  }
  print('All users\' followers and following counts reset to 0.');
}
