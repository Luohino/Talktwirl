import 'package:flutter/material.dart';

class InboxRefreshNotifier extends ValueNotifier<int> {
  InboxRefreshNotifier() : super(0);
  void refresh() => value++;
}

final inboxRefreshNotifier = InboxRefreshNotifier(); 