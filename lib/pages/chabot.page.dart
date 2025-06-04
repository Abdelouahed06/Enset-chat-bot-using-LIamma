import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;

class ChabotPage extends StatefulWidget {
  const ChabotPage({super.key});

  @override
  State<ChabotPage> createState() => _ChabotPageState();
}

class _ChabotPageState extends State<ChabotPage> {
  final List<Map<String, String>> _messages = [];
  final List<List<Map<String, String>>> _savedConversations = [];
  final TextEditingController _userController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isLoadingResponse = false;
  StreamSubscription<String>? _responseSubscription;
  http.Client? _httpClient;

  @override
  void dispose() {
    _userController.dispose();
    _scrollController.dispose();
    _responseSubscription?.cancel();
    _httpClient?.close();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    if (_userController.text.trim().isEmpty || _isLoadingResponse) return;

    final question = _userController.text.trim();
    _userController.clear();

    setState(() {
      _messages.add({"role": "user", "content": question});
      _isLoadingResponse = true;
    });

    _scrollToBottom();

    try {
      _httpClient = http.Client();
      final uri = Uri.parse("http://localhost:11434/api/chat");
      final headers = {"Content-Type": "application/json"};
      final body = {"model": "tinydolphin", "messages": _messages};

      final request = http.Request('POST', uri)
        ..headers.addAll(headers)
        ..body = json.encode(body);

      setState(() {
        _messages.add({"role": "assistant", "content": ""});
      });

      final response = await _httpClient!.send(request);
      _responseSubscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (String line) {
          if (line.isNotEmpty) {
            try {
              final jsonResponse = json.decode(line);
              if (jsonResponse['message'] != null &&
                  jsonResponse['message']['content'] != null) {
                final content = jsonResponse['message']['content'];
                setState(() {
                  _messages.last['content'] = (_messages.last['content'] ?? '') + content;
                  _scrollToBottom();
                });
              }
            } catch (e) {
              debugPrint("Error decoding JSON line: $e");
              debugPrint("Line causing error: $line");
            }
          }
        },
        onDone: () {
          setState(() => _isLoadingResponse = false);
          _scrollToBottom();
        },
        onError: (error) {
          setState(() {
            _messages.last['content'] = "${_messages.last['content'] ?? ''}\nError: ${error.toString()}";
            _isLoadingResponse = false;
          });
          _scrollToBottom();
        },
      );
    } catch (err) {
      setState(() {
        _messages.add({
          "role": "assistant",
          "content": "Failed to connect to the chatbot service. Error: $err"
        });
        _isLoadingResponse = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _startNewChat() {
    if (_messages.isNotEmpty) {
      _savedConversations.add(List.from(_messages));
    }
    setState(() {
      _messages.clear();
      _userController.clear();
    });
  }

  void _loadConversation(int index) {
    setState(() {
      _messages.clear();
      _messages.addAll(_savedConversations[index]);
      _userController.clear();
    });
    Navigator.pop(context);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        child: Column(
          children: [
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.primaryColor,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.centerLeft,
              child: const Text(
                'Saved Conversations',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: _savedConversations.isEmpty
                  ? Center(
                      child: Text(
                        'No saved conversations',
                        style: TextStyle(
                          fontSize: 16, 
                          color: Colors.grey,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: _savedConversations.length,
                      itemBuilder: (context, index) {
                        final conversation = _savedConversations[index];
                        String preview = "New Chat";
                        if (conversation.isNotEmpty &&
                            conversation[0]['content']!.isNotEmpty) {
                          preview = conversation[0]['content']!.substring(
                              0,
                              min(conversation[0]['content']!.length, 30));
                          if (conversation[0]['content']!.length > 30) {
                            preview += "...";
                          }
                        }
                        return Container(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.grey.withOpacity(0.1),
                                width: 1,
                              ),
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.chat_bubble_outline, size: 20),
                            title: Text(
                              'Conversation ${index + 1}',
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              preview,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _loadConversation(index),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () {
                                setState(() {
                                  _savedConversations.removeAt(index);
                                });
                              },
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: Text(
          "DWM Chatbot",
          style: TextStyle(color: theme.indicatorColor),
        ),
        backgroundColor: theme.primaryColor,
        leading: IconButton(
          icon: Icon(Icons.menu, color: theme.indicatorColor),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.pushReplacementNamed(context, "/");
            },
            icon: Icon(Icons.logout, color: theme.indicatorColor),
          ),
          IconButton(
            onPressed: _startNewChat,
            icon: Icon(Icons.note_add, color: theme.indicatorColor),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat,
                          size: 64,
                          color: theme.hintColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Start a new conversation",
                          style: TextStyle(
                            color: theme.hintColor,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isUser = message['role'] == 'user';
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Align(
                          alignment: isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.8,
                            ),
                            child: Card(
                              color: isUser
                                  ? theme.primaryColor.withOpacity(0.1)
                                  : isDarkMode
                                      ? Colors.grey[800]
                                      : Colors.white,
                              elevation: 1,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: isUser
                                      ? const Radius.circular(16)
                                      : const Radius.circular(4),
                                  bottomRight: isUser
                                      ? const Radius.circular(4)
                                      : const Radius.circular(16),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Text(
                                  message['content']!,
                                  style: TextStyle(
                                    color: isUser
                                        ? theme.primaryColor
                                        : theme.textTheme.bodyLarge?.color,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_isLoadingResponse)
            const LinearProgressIndicator(
              minHeight: 2,
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _userController,
                    decoration: InputDecoration(
                      hintText: "Type a message...",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: isDarkMode ? Colors.grey[800] : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _sendMessage,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                    textInputAction: TextInputAction.send,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}