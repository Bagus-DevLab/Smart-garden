import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_farming/cubit/chat/chat_cubit.dart';
import 'package:smart_farming/models/chat_message.dart';
import 'package:smart_farming/theme/app_colors.dart'; // Sesuaikan lokasi file warna kamu

class ChatBottomSheet extends StatefulWidget {
  const ChatBottomSheet({super.key});

  @override
  State<ChatBottomSheet> createState() => _ChatBottomSheetState();
}

class _ChatBottomSheetState extends State<ChatBottomSheet> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Fungsi agar chat otomatis scroll ke paling bawah kalau ada pesan baru
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 100,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Kita atur tingginya 75% dari layar HP
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          // --- BAGIAN 1: HEADER (JUDUL) ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Asisten Tani AI",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context), // Tutup chat
                )
              ],
            ),
          ),

          // --- BAGIAN 2: LIST PESAN (BODY) ---
          Expanded(
            child: BlocConsumer<ChatCubit, ChatState>(
              listener: (context, state) {
                if (state is ChatLoaded) {
                  // Kalau pesan masuk, scroll ke bawah
                  Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
                }
              },
              builder: (context, state) {
                if (state is ChatLoaded) {
                  if (state.messages.isEmpty) {
                    return const Center(child: Text("Halo! Ada yang bisa saya bantu?"));
                  }
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: state.messages.length + (state.isTyping ? 1 : 0),
                    itemBuilder: (context, index) {
                      // Tampilkan animasi "Sedang mengetik..."
                      if (index == state.messages.length) {
                        return const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text("Sedang mengetik...", style: TextStyle(fontStyle: FontStyle.italic)),
                        );
                      }
                      return _buildChatBubble(state.messages[index]);
                    },
                  );
                }
                return const Center(child: CircularProgressIndicator());
              },
            ),
          ),

          // --- BAGIAN 3: INPUT FIELD (TEMPAT KETIK) ---
          Container(
            padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 10,
                bottom: MediaQuery.of(context).viewInsets.bottom + 10 // Agar naik saat keyboard muncul
            ),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Tanya sesuatu...',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton.small(
                  backgroundColor: AppColors.primary, // Ganti warna sesuai tema
                  child: const Icon(Icons.send, color: Colors.white),
                  onPressed: () {
                    if (_controller.text.isNotEmpty) {
                      // Panggil fungsi kirim di Cubit
                      context.read<ChatCubit>().sendMessage(_controller.text);
                      _controller.clear();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Desain Bubble Chat
  Widget _buildChatBubble(ChatMessage msg) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: msg.isUser ? AppColors.primary : Colors.grey[300],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(15),
            topRight: const Radius.circular(15),
            bottomLeft: msg.isUser ? const Radius.circular(15) : Radius.zero,
            bottomRight: msg.isUser ? Radius.zero : const Radius.circular(15),
          ),
        ),
        // Batasi lebar bubble max 70% layar
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        child: Text(
          msg.text,
          style: TextStyle(color: msg.isUser ? Colors.white : Colors.black),
        ),
      ),
    );
  }
}