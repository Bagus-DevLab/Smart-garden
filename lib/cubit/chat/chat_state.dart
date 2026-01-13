part of 'chat_cubit.dart';

abstract class ChatState {}

class ChatInitial extends ChatState {}

class ChatLoaded extends ChatState {
  final List<ChatMessage> messages;
  final bool isTyping; // Untuk animasi loading bot

  ChatLoaded({required this.messages, this.isTyping = false});
}

class ChatError extends ChatState {
  final String message;
  ChatError(this.message);
}