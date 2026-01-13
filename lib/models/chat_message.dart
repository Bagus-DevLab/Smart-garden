class ChatMessage {
  final String text;
  final bool isUser; // True = User, False = Bot
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}