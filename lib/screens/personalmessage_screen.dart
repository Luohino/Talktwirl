import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:async';
import '../core/supabase_client.dart';
import '../core/supabase_message_service.dart';
import '../screens/user_profile_screen.dart';
import 'home_screen.dart';
import 'package:hive/hive.dart';
import 'package:flutter/gestures.dart';
import 'package:swipe_to/swipe_to.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../core/inbox_notifier.dart';

class PersonalMessageScreen extends StatefulWidget {
  final String username;
  final String avatarAsset;
  final String name;
  final String otherUserId; // Add this parameter

  PersonalMessageScreen({Key? key, required this.username, required this.avatarAsset, required this.name, required this.otherUserId}) : super(key: key);

  @override
  State<PersonalMessageScreen> createState() => _PersonalMessageScreenState();
}

class _PersonalMessageScreenState extends State<PersonalMessageScreen> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _editController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  int? _selectedMsgIndex;
  bool _isEditing = false;
  OverlayEntry? _actionBarOverlay;
  String? _pickedImagePath;
  int? _actionBarMsgIndex;
  Timer? _holdTimer;
  late final String _currentUserId;
  late final String _otherUserId;
  late final SupabaseMessageService _dmService;
  List<Map<String, dynamic>> _messages = [];
  Stream<List<Map<String, dynamic>>>? _messageStream;
  bool _isConnected = true;
  bool _isLoading = true;
  bool _isFullyLoaded = false;
  String? _connectionError;
  double _swipeDx = 0;
  bool _otherUserOnline = false;
  StreamSubscription? _profileSub;
  Map<String, Map<String, dynamic>>? _userProfilesCache;
  double _dragDx = 0.0;
  
  // Prevent excessive rebuilds
  String _lastMessageHash = '';
  bool _isProcessingUpdate = false;

  @override
  void initState() {
    super.initState();
    _checkUserSuspended();
    _scrollController.addListener(_onScroll);
    _currentUserId = SupabaseService.client.auth.currentUser?.id ?? '';
    _otherUserId = widget.otherUserId;
    _dmService = SupabaseMessageService(SupabaseService.client);
    _initSupabaseDM();
    _focusNode.addListener(_onFocusChange);
    _listenToOtherUserOnlineStatus();
    _markMessagesAsRead();
    // Try to get the user profiles cache from HomeScreenBody if available
    final homeScreenBodyState = context.findAncestorStateOfType<HomeScreenBodyState>();
    if (homeScreenBodyState != null) {
      _userProfilesCache = homeScreenBodyState.userProfilesCache;
    } else {
      // Load from Hive cache if not available from HomeScreenBody
      final profilesBox = Hive.box('profiles');
      _userProfilesCache = Map<String, Map<String, dynamic>>.fromEntries(
        profilesBox.toMap().entries.map((e) => MapEntry(e.key.toString(), Map<String, dynamic>.from(e.value)))
      );
    }
    // Load cached messages for this chat immediately
    final messagesBox = Hive.box('messages');
    final user = SupabaseService.client.auth.currentUser;
    if (user != null) {
      final cached = messagesBox.values.where((msg) =>
        (msg['sender_id'] == user.id && msg['receiver_id'] == widget.otherUserId) ||
        (msg['sender_id'] == widget.otherUserId && msg['receiver_id'] == user.id)
      ).toList();
      if (cached.isNotEmpty) {
        // Sort messages by timestamp
        cached.sort((a, b) {
          final aTime = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime.now();
          final bTime = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime.now();
          return aTime.compareTo(bTime);
        });
        setState(() {
          _messages = cached.map((m) => Map<String, dynamic>.from(m as Map)).toList();
          _isLoading = false;
        });
        // Process the cached messages to match the expected format
        _messages = _processMessages(_messages);
        // Scroll to bottom after loading cached messages
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    }
    
    // Set a timer to show content even if network is slow
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && !_isFullyLoaded && _messages.isNotEmpty) {
        setState(() {
          _isFullyLoaded = true;
        });
      }
    });
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      // Delay to allow keyboard to animate up, then scroll to bottom
      Future.delayed(const Duration(milliseconds: 300), _scrollToBottom);
    }
  }

  Future<void> _submitMessage(String text) async {
    if (text.isEmpty || _currentUserId.isEmpty || _otherUserId.isEmpty) return;

    final optimisticMessageId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticMessage = {
      'id': optimisticMessageId,
      'content': text,
      'type': 'text',
      'isMe': true,
      'timestamp': DateTime.now().toIso8601String(),
      'is_read': false,
      'deleted': false,
      'edited_at': null,
      'reply_to': null,
      'reaction': null,
      'attachment_url': null,
    };

    setState(() {
      _messages.add(optimisticMessage);
    });
    _scrollToBottom();

    try {
      await _dmService.sendMessage(_currentUserId, _otherUserId, text);
      // Message sent successfully - the real-time stream will handle updating the UI
      // Don't remove the optimistic message here, let the stream replace it
    } catch (e) {
      // On error, remove the optimistic message
      setState(() {
        _messages.removeWhere((msg) => msg['id'] == optimisticMessageId);
      });

      if (mounted) {
        String errorMessage;
        if (e.toString().contains('SocketException')) {
          errorMessage = 'No internet connection. Please try again.';
        } else {
          errorMessage = 'Failed to send message.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _submitMessage(text),
            ),
          ),
        );
      }
    }
  }

  bool _isSending = false; // Add this to prevent double-sends
  
  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isNotEmpty && !_isSending) {
      _isSending = true;
      _controller.clear();
      await _submitMessage(text);
      inboxRefreshNotifier.refresh();
      _isSending = false;
      // Don't save optimistic message to Hive - let the real message from server handle this
    }
  }

  Future<void> _initSupabaseDM() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    
    // Only set loading if we don't have cached messages
    if (_messages.isEmpty && mounted) {
      setState(() {
        _isLoading = true;
        _connectionError = null;
      });
    }
    
    // Initialize with existing messages first
    try {
      final initialMessages = await _dmService.fetchMessageHistory(_currentUserId, _otherUserId);
      // Save all fetched messages to Hive for offline use
      final messagesBox = Hive.box('messages');
      for (final msg in initialMessages) {
        if (msg['id'] != null) {
          messagesBox.put(msg['id'], msg);
        }
      }
      final processedMessages = _processMessages(initialMessages);
      
      // Only update state if we have new messages or different messages
      if (_messages.isEmpty || 
          processedMessages.length != _messages.length || 
          (processedMessages.isNotEmpty && _messages.isNotEmpty && 
           processedMessages.last['id'] != _messages.last['id'])) {
        setState(() {
          _messages = processedMessages;
          _isLoading = false;
          _isFullyLoaded = true;
        });
        _scrollToBottom();
      } else if (_isLoading) {
        setState(() {
          _isLoading = false;
          _isFullyLoaded = true;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isFullyLoaded = true;
        _connectionError = e.toString();
        _isConnected = false;
      });
    }
    
    // Set up real-time stream with error handling
    try {
      setState(() {
        _messageStream = _dmService.subscribeToDM(_currentUserId, _otherUserId);
      });
      
      // Mark messages as read when chat opens
      await _dmService.markMessagesAsRead(_currentUserId, _otherUserId);
    } catch (e) {
      setState(() {
        _connectionError = e.toString();
        _isConnected = false;
      });
    }
  }

  List<Map<String, dynamic>> _processMessages(List<Map<String, dynamic>> rawMessages) {
    // Sort messages by timestamp ascending (oldest first)
    rawMessages.sort((a, b) {
      final aTime = DateTime.tryParse(a['timestamp'] ?? a['created_at'] ?? '') ?? DateTime.now();
      final bTime = DateTime.tryParse(b['timestamp'] ?? b['created_at'] ?? '') ?? DateTime.now();
      return aTime.compareTo(bTime);
    });
    final processedMessages = <Map<String, dynamic>>[];
    for (final msg in rawMessages) {
      // Skip messages with null or empty ID
      if (msg['id'] == null) continue;
      
      final isMe = msg['sender_id'] == _currentUserId;
      final messageData = {
        'id': msg['id'].toString(),
        'content': (msg['message_text'] ?? msg['content'] ?? '').toString(),
        'type': 'text',
        'isMe': isMe,
        'timestamp': (msg['created_at'] ?? msg['timestamp'] ?? DateTime.now().toIso8601String()).toString(),
        'is_read': msg['is_read'] ?? false,
        'deleted': msg['deleted'] ?? false,
        'edited_at': msg['edited_at']?.toString(),
        'reply_to': msg['reply_to']?.toString(),
        'reaction': msg['reaction'],
        'attachment_url': msg['attachment_url']?.toString(),
      };
      processedMessages.add(messageData);
    }
    return processedMessages;
  }

  String _formatTimestamp(String? timestamp) {
    if (timestamp == null) return '';
    
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      
      if (difference.inDays > 0) {
        return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'now';
      }
    } catch (e) {
      return '';
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _pickImage() async {
    final picker = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picker != null) {
      setState(() {
        _messages.add({
          'type': 'image',
          'content': picker.path,
          'caption': '',
          'time': TimeOfDay.now().format(context),
          'isMe': true,
        });
      });
      _scrollToBottom();
    }
  }

  void _showActionBar(BuildContext context, int msgIndex, GlobalKey key) {
    // Prevent showing if already shown for this message
    if (_actionBarOverlay != null && _actionBarMsgIndex == msgIndex) {
      return;
    }

    final RenderBox? renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final offset = renderBox.localToGlobal(Offset.zero);
      _actionBarOverlay?.remove();
      _actionBarOverlay = OverlayEntry(
        builder: (context) => Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _hideActionBar,
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: offset.dx,
              top: offset.dy - 56,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.reply, color: Colors.white),
                        onPressed: () {
                          _hideActionBar();
                          setState(() {
                            _selectedMsgIndex = msgIndex;
                            _controller.text = '';
                          });
                        },
                        tooltip: 'Reply',
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.white),
                        onPressed: () async {
                          _actionBarOverlay?.remove();
                          _actionBarOverlay = null;
                          final newText = await showDialog<String>(
                            context: context,
                            builder: (context) {
                              final editController = TextEditingController(text: _messages[msgIndex]['content']);
                              return AlertDialog(
                                backgroundColor: const Color(0xFF261531),
                                title: const Text('Edit Message', style: TextStyle(color: Colors.white)),
                                content: TextField(
                                  controller: editController,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, null),
                                    child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, editController.text),
                                    child: const Text('Save', style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              );
                            },
                          );
                          if (newText != null && newText.trim().isNotEmpty) {
                            await _dmService.editMessage(_messages[msgIndex]['id'], newText.trim());
                          }
                          setState(() {
                            _selectedMsgIndex = null;
                          });
                        },
                        tooltip: 'Edit',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.white),
                        onPressed: () async {
                          await _dmService.softDeleteMessage(_messages[msgIndex]['id']);
                          setState(() {
                            _selectedMsgIndex = null;
                          });
                          _hideActionBar();
                        },
                        tooltip: 'Delete',
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, color: Colors.white),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _messages[msgIndex]['content']));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
                          _hideActionBar();
                        },
                        tooltip: 'Copy',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      Overlay.of(context).insert(_actionBarOverlay!);
      _actionBarMsgIndex = msgIndex;
    }
  }

  void _hideActionBar() {
    _actionBarOverlay?.remove();
    _actionBarOverlay = null;
    setState(() {
      _selectedMsgIndex = null;
      _actionBarMsgIndex = null;
    });
  }

  void _onScroll() {
    if (_actionBarOverlay != null) {
      _hideActionBar(); // Hide action bar on scroll
    }
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
                child: const Text('Log out', style: TextStyle(color: Colors.purpleAccent)),
              ),
            ],
          ),
        );
      }
    }
  }

  void _listenToOtherUserOnlineStatus() {
    _profileSub?.cancel();
    _profileSub = SupabaseService.client
      .from('profiles:id=eq.${widget.otherUserId}')
      .stream(primaryKey: ['id'])
      .listen((event) {
        if (event.isNotEmpty) {
          final profile = event.first;
          setState(() {
            _otherUserOnline = profile['is_online'] == true;
          });
        }
      });
  }

  void _markMessagesAsRead() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    await SupabaseService.client
      .from('messages')
      .update({'is_read': true})
      .eq('receiver_id', user.id)
      .eq('sender_id', widget.otherUserId)
      .eq('is_read', false);
  }

  @override
  void dispose() {
    _controller.dispose();
    _editController.dispose();
    _actionBarOverlay?.remove();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _holdTimer?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _profileSub?.cancel();
    super.dispose();
  }

  // Add this helper function to check if user is at the bottom
  bool _isAtBottom() {
    if (!_scrollController.hasClients) return true;
    return _scrollController.offset >= _scrollController.position.maxScrollExtent - 50;
  }

  @override
  Widget build(BuildContext context) {
    final messageCount = _messages.where((m) => m['type'] == 'text' || m['type'] == 'image' || m['type'] == 'voice').length;
    
    // Show loading screen until fully loaded
    if (!_isFullyLoaded && (_isLoading || _messages.isEmpty)) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Row(
            children: [
              CircleAvatar(
                backgroundImage: widget.avatarAsset.startsWith('http')
                  ? NetworkImage(widget.avatarAsset) as ImageProvider
                  : AssetImage(widget.avatarAsset),
                radius: 20,
              ),
              const SizedBox(width: 8),
              Text(widget.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 20),
              Text('Loading messages...', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => UserProfileScreen(
                  userData: {
                    'uid': widget.otherUserId,
                    'username': widget.username,
                    'name': widget.name,
                    'profilePhoto': widget.avatarAsset,
                  },
                  isCurrentUser: false,
                ),
              ),
            );
          },
          child: Row(
            children: [
              CircleAvatar(
                backgroundImage: widget.avatarAsset.startsWith('http')
                  ? NetworkImage(widget.avatarAsset) as ImageProvider
                  : AssetImage(widget.avatarAsset),
                radius: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    Row(
                      children: [
                        Text('@${widget.username}', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                        const SizedBox(width: 8),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _otherUserOnline ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        if (!_otherUserOnline) ...[
                          const SizedBox(width: 4),
                          const Text('Offline', style: TextStyle(color: Colors.red, fontSize: 11)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call, color: Colors.white),
            tooltip: 'Audio Call',
            onPressed: () {
              // TODO: Integrate audio call logic here
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Audio call feature coming soon!')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.videocam, color: Colors.white),
            tooltip: 'Video Call',
            onPressed: () {
              // TODO: Integrate video call logic here
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Video call feature coming soon!')),
              );
            },
          ),
          if (!_isConnected)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () => _initSupabaseDM(),
              tooltip: 'Reconnect',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _messageStream,
              builder: (context, snapshot) {
                // Handle loading state
                if (_isLoading && _messages.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading messages...', style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  );
                }
                
                // Handle connection errors
                if (snapshot.hasError || _connectionError != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _isConnected = false;
                        _connectionError = snapshot.error?.toString() ?? _connectionError;
                      });
                    }
                  });
                  
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.signal_wifi_off, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        const Text('Connection Lost', style: TextStyle(color: Colors.white, fontSize: 18)),
                        const SizedBox(height: 8),
                        Text(
                          _connectionError ?? 'Unable to connect to chat',
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => _initSupabaseDM(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reconnect'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8F5CFF),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Handle waiting state
                if (snapshot.connectionState == ConnectionState.waiting && _messages.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Connecting to chat...', style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  );
                }

                // Update connection status
                if (snapshot.connectionState == ConnectionState.active) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _isConnected = true;
                        _connectionError = null;
                      });
                    }
                  });
                }

                // Update messages with real-time data
                if (snapshot.hasData && snapshot.data != null && !_isProcessingUpdate) {
                  final newMessages = _processMessages(snapshot.data!);
                  
                  // Create hash to check if update is needed
                  final newMessageHash = newMessages.map((m) => '${m['id']}_${m['is_read']}_${m['timestamp']}').join('|');
                  if (newMessageHash != _lastMessageHash) {
                  
                    // Save all new messages to Hive
                    final messagesBox = Hive.box('messages');
                    for (final msg in snapshot.data!) {
                      if (msg['id'] != null) {
                        messagesBox.put(msg['id'], msg);
                      }
                    }
                    
                    // Handle optimistic message replacement
                    List<Map<String, dynamic>> updatedMessages = List.from(newMessages);
                    
                    // Check if we have optimistic messages that need to be replaced
                    final optimisticMessages = _messages.where((m) => m['id'].toString().startsWith('temp_')).toList();
                    
                    if (optimisticMessages.isNotEmpty) {
                      // Remove optimistic messages that have been confirmed by server
                      for (final optimistic in optimisticMessages) {
                        // Look for matching server message with same content and from same user
                        final matchingServerMessages = newMessages.where((serverMsg) => 
                          serverMsg['content'].toString().trim() == optimistic['content'].toString().trim() &&
                          serverMsg['isMe'] == true &&
                          DateTime.parse(serverMsg['timestamp']).difference(DateTime.parse(optimistic['timestamp'])).abs().inSeconds < 60
                        );
                        
                        if (matchingServerMessages.isNotEmpty) {
                          // Server message found, remove optimistic message from local list
                          _messages.removeWhere((msg) => msg['id'] == optimistic['id']);
                        }
                      }
                      
                      // Add any remaining optimistic messages to the end (messages still being sent)
                      final remainingOptimistic = _messages.where((m) => m['id'].toString().startsWith('temp_')).toList();
                      if (remainingOptimistic.isNotEmpty) {
                        updatedMessages.addAll(remainingOptimistic);
                        
                        // Sort by timestamp to maintain order
                        updatedMessages.sort((a, b) {
                          final aTime = DateTime.tryParse(a['timestamp'] ?? '') ?? DateTime.now();
                          final bTime = DateTime.tryParse(b['timestamp'] ?? '') ?? DateTime.now();
                          return aTime.compareTo(bTime);
                        });
                      }
                    }
                    
                    // Update UI if the lists are different
                    bool shouldUpdate = _messages.length != updatedMessages.length;
                    if (!shouldUpdate && _messages.isNotEmpty && updatedMessages.isNotEmpty) {
                      // Check if any message content or status has changed
                      for (int i = 0; i < _messages.length && i < updatedMessages.length; i++) {
                        if (_messages[i]['id'] != updatedMessages[i]['id'] ||
                            _messages[i]['content'] != updatedMessages[i]['content'] ||
                            _messages[i]['is_read'] != updatedMessages[i]['is_read']) {
                          shouldUpdate = true;
                          break;
                        }
                      }
                    }
                    
                    if (shouldUpdate) {
                      _isProcessingUpdate = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _messages = updatedMessages;
                            _isLoading = false;
                            _lastMessageHash = newMessageHash;
                          });
                          // Only scroll to bottom if user is already at the bottom
                          if (_isAtBottom()) {
                            _scrollToBottom();
                          }
                        }
                        _isProcessingUpdate = false;
                      });
                    }
                  }
                }

                if (_messages.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, color: Colors.white54, size: 64),
                        SizedBox(height: 16),
                        Text('No messages yet', style: TextStyle(color: Colors.white70, fontSize: 18)),
                        SizedBox(height: 8),
                        Text('Start a conversation!', style: TextStyle(color: Colors.white54, fontSize: 14)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  itemCount: _messages.length,
                  // Add itemExtent for fixed height if possible, remove msgKey
                  // itemExtent: 72.0, // Uncomment and adjust if all items have similar height
                  itemBuilder: (context, i) {
                    final msg = _messages[i];
                    if (msg['type'] == 'date') {
                      return const Row(
                        children: [
                          Expanded(child: Divider(color: Colors.white24, endIndent: 8)),
                          Text('Date', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          Expanded(child: Divider(color: Colors.white24, indent: 8)),
                        ],
                      );
                    } else if (msg['type'] == 'text' || msg['type'] == 'image') {
                      final isMe = msg['isMe'] == true;
                      final isUnreadIncoming = !isMe && msg['is_read'] == false;
                      final isSelected = _selectedMsgIndex == i;
                      // Removed: final msgKey = GlobalKey();

                      // Handle deleted message
                      if (msg['deleted'] == true) {
                        return Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey[800]?.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Message deleted', 
                              style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 12),
                            ),
                          ),
                        );
                      }

                      // Handle reactions
                      List<Widget> reactionWidgets = [];
                      if (msg['reaction'] != null && msg['reaction'] is Map) {
                        (msg['reaction'] as Map).forEach((emoji, count) {
                          reactionWidgets.add(
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text('$emoji $count', style: const TextStyle(fontSize: 14)),
                            ),
                          );
                        });
                      }

                      // Custom swipe-to-reply implementation
                      return GestureDetector(
                        // key: msgKey, // Removed GlobalKey
                        onHorizontalDragStart: (_) {
                          _dragDx = 0.0;
                        },
                        onHorizontalDragUpdate: (details) {
                          _dragDx += details.delta.dx;
                          if (_dragDx > 40) {
                            // setState(() {
                            //   _replyToMessageId = msg['id'];
                            // });
                            _dragDx = 0.0;
                          }
                        },
                        onHorizontalDragEnd: (_) {
                          _dragDx = 0.0;
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          child: Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(vertical: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: isMe ? Colors.white10 : Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                          border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              msg['content'] + (msg['edited_at'] != null ? ' (edited)' : ''),
                                              style: TextStyle(
                                                color: isMe ? Colors.white : Colors.black,
                                                fontWeight: isUnreadIncoming ? FontWeight.bold : FontWeight.normal,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (reactionWidgets.isNotEmpty) ...reactionWidgets,
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isMe && msg['is_read'] == true)
                                      const Icon(Icons.done_all, size: 16, color: Colors.blueAccent),
                                    if (isMe && msg['is_read'] == false)
                                      const Icon(Icons.done, size: 16, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatTimestamp(msg['timestamp']),
                                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    } else if (msg['type'] == 'voice') {
                      // Remove audio message from chat
                      return const SizedBox.shrink();
                    }
                    return const SizedBox.shrink();
                  },
                );
              },
            ),
          ),
          // REMOVED: if (_replyToMessageId != null) ...[
          //   Container(
          //     margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          //     padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          //     decoration: BoxDecoration(
          //       color: Colors.grey[800],
          //       borderRadius: BorderRadius.circular(10),
          //     ),
          //     child: Row(
          //       children: [
          //         Expanded(
          //           child: Builder(
          //             builder: (context) {
          //               final repliedMsg = _messages.firstWhere(
          //                 (m) => m['id'] == _replyToMessageId,
          //                 orElse: () => {'content': '[Original message unavailable]', 'isMe': false},
          //               );
          //               final isMe = repliedMsg['isMe'] == true;
          //               final content = repliedMsg['content'] ?? '[Original message unavailable]';
          //               return RichText(
          //                 text: TextSpan(
          //                   children: [
          //                     if (isMe)
          //                       const TextSpan(
          //                         text: 'You: ',
          //                         style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          //                       ),
          //                     TextSpan(
          //                       text: content,
          //                       style: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic, fontSize: 13),
          //                     ),
          //                   ],
          //                 ),
          //                 maxLines: 2,
          //                 overflow: TextOverflow.ellipsis,
          //               );
          //             },
          //           ),
          //         ),
          //         IconButton(
          //           icon: const Icon(Icons.close, color: Colors.white54, size: 20),
          //           onPressed: () {
          //             setState(() {
          //               _replyToMessageId = null;
          //             });
          //           },
          //           tooltip: 'Cancel reply',
          //         ),
          //       ],
          //     ),
          //   ),
          // ],
          SafeArea(
            minimum: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      decoration: const InputDecoration(
                        hintText: 'Type a message',
                        hintStyle: TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: Colors.black,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(30)),
                          borderSide: BorderSide(color: Colors.white, width: 1.2),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(30)),
                          borderSide: BorderSide(color: Colors.white, width: 1.2),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(30)),
                          borderSide: BorderSide(color: Colors.white, width: 1.5),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
