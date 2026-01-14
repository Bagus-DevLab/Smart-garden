import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_farming/models/chat_message.dart';
import 'package:smart_farming/services/chat_service.dart';

part 'chat_state.dart';

class ChatCubit extends Cubit<ChatState> {
  final ChatService _chatService;

  ChatCubit(this._chatService) : super(ChatLoaded(messages: []));

  List<ChatMessage> _messages = [];

  // Fungsi Kirim Pesan
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    // 1. Tambahkan pesan User ke layar dulu (Optimistic UI)
    final userMsg = ChatMessage(text: text, isUser: true, timestamp: DateTime.now());
    _messages.add(userMsg);

    // Emit state loading (Bot is typing...)
    emit(ChatLoaded(messages: List.from(_messages), isTyping: true));

    try {
      // 2. Kirim ke API
      final response = await _chatService.sendMessage(text);

      // 3. Tambahkan balasan Bot
      final botMsg = ChatMessage(text: response, isUser: false, timestamp: DateTime.now());
      _messages.add(botMsg);

      emit(ChatLoaded(messages: List.from(_messages), isTyping: false));
    } catch (e) {
      // Jika error (misal kuota habis), tampilkan pesan error tapi jangan hapus chat history
      emit(ChatLoaded(messages: List.from(_messages), isTyping: false));
      // Kamu bisa emit state Error khusus untuk Snackbar, atau masukkan error sebagai pesan bot
      _messages.add(ChatMessage(
          text: "[SISTEM] ${e.toString().replaceAll('Exception: ', '')}",
          isUser: false,
          timestamp: DateTime.now()
      ));
      emit(ChatLoaded(messages: List.from(_messages)));
    }
  }
}