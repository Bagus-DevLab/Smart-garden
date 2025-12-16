import 'dart:async';
import 'package:flutter/material.dart';

// Sesuaikan path import ini dengan lokasi AuthService Anda
import '../../cubit/auth_service.dart';

import 'dashboard.dart';
import 'login_page.dart';

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key});

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  final AuthService _authService = AuthService();
  Timer? _timer;
  bool _isSendingVerification = false;

  @override
  void initState() {
    super.initState();
    // Pastikan pengguna ada sebelum memulai pengecekan
    if (_authService.currentUser != null) {
      // Mulai timer untuk memeriksa status verifikasi secara berkala
      _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
        checkEmailVerified();
      });
    }
  }

  @override
  void dispose() {
    // Selalu batalkan timer saat halaman tidak lagi digunakan untuk mencegah memory leak
    _timer?.cancel();
    super.dispose();
  }

  Future<void> checkEmailVerified() async {
    // Memuat ulang data pengguna dari Firebase untuk mendapatkan status terbaru
    await _authService.reloadUser();

    // Jika email sudah terverifikasi, batalkan timer dan arahkan ke dashboard
    if (_authService.isEmailVerified) {
      _timer?.cancel();
      // Menggunakan pushReplacement agar pengguna tidak bisa kembali ke halaman verifikasi
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const Dashboard()),
      );
    }
  }

  Future<void> resendVerificationEmail() async {
    if (_isSendingVerification) return; // Mencegah klik ganda

    setState(() => _isSendingVerification = true);

    try {
      await _authService.sendEmailVerification();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email verifikasi baru telah dikirim.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengirim email: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isSendingVerification = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Verifikasi Email Anda"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Email verifikasi telah dikirim ke:',
                style: Theme
                    .of(context)
                    .textTheme
                    .titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _authService.currentUser?.email ?? 'Email tidak ditemukan',
                style: Theme
                    .of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              const Text(
                'Silakan periksa kotak masuk (dan folder spam) Anda, lalu klik tautan verifikasi untuk melanjutkan.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                icon: _isSendingVerification
                    ? const SizedBox(width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.email),
                label: const Text('Kirim Ulang Email'),
                onPressed: resendVerificationEmail,
              ),
              TextButton(
                child: const Text('Batalkan & Logout'),
                onPressed: () async {
                  _timer?.cancel();
                  await _authService.signOut();
                  // Arahkan kembali ke halaman login
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                        (route) => false, // Hapus semua rute sebelumnya
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}