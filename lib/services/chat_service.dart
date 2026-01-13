import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class ChatService {
  // Gunakan 10.0.2.2 untuk Emulator Android mengakses Localhost Laptop
  // Jika pakai HP Fisik, ganti dengan IP Laptop (misal 192.168.1.x)
  final String baseUrl = 'http://chatbot.smartfarmingpalcomtech.my.id/chat';

  Future<String> sendMessage(String message) async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User belum login');

      // 1. Ambil Token terbaru
      String? token = await user.getIdToken();

// 2. Cek jika null, lempar error
      if (token == null) {
        throw Exception('Gagal mengambil token autentikasi');
      }

      // 2. Kirim ke Python Backend
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'message': message}),
      );

      // 3. Cek Response
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['response']; // Ambil text balasan bot
      } else if (response.statusCode == 429) {
        throw Exception('Kuota harian habis (Maks 5 chat). Besok lagi ya!');
      } else {
        throw Exception('Gagal: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception(e.toString());
    }
  }
}