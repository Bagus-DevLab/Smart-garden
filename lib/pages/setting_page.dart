import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_farming/cubit/auth/auth_cubit.dart';
import 'package:smart_farming/theme/app_colors.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // State untuk Toggle (Simulasi)
  bool _notifEnabled = true;
  bool _biometricEnabled = false;

  @override
  Widget build(BuildContext context) {
    // Ambil user saat ini dari AuthCubit / Firebase
    final user = context.watch<AuthCubit>().currentUser;

    return Scaffold(
      backgroundColor: AppColors.surfaceVariant,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceVariant,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Pengaturan",
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ================= BAGIAN AKUN =================
            _buildSectionHeader("Akun & Keamanan"),
            const SizedBox(height: 10),

            // Kartu Profil Mini
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    child: Icon(Icons.person, color: AppColors.primary),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? "User",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          user?.email ?? "",
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.edit, size: 20, color: AppColors.accent),
                    onPressed: () => _showEditNameDialog(context, user),
                  )
                ],
              ),
            ),

            const SizedBox(height: 15),

            // Menu Ubah Password
            _buildSettingsItem(
              icon: Icons.lock_outline_rounded,
              title: "Ubah Password",
              subtitle: "Perbarui kata sandi akun Anda",
              onTap: () => _showChangePasswordDialog(context, user),
            ),

            const SizedBox(height: 25),

            // ================= BAGIAN APLIKASI =================
            _buildSectionHeader("Preferensi Aplikasi"),
            const SizedBox(height: 10),

            _buildSwitchItem(
              icon: Icons.notifications_outlined,
              title: "Notifikasi Push",
              value: _notifEnabled,
              onChanged: (val) {
                setState(() => _notifEnabled = val);
                // Tambahkan logika simpan ke SharedPreferences di sini
              },
            ),

            _buildSwitchItem(
              icon: Icons.fingerprint,
              title: "Login Biometrik",
              value: _biometricEnabled,
              onChanged: (val) {
                setState(() => _biometricEnabled = val);
                // Tambahkan logika simpan ke SharedPreferences di sini
              },
            ),

            const SizedBox(height: 25),

            // ================= TENTANG =================
            _buildSectionHeader("Lainnya"),
            const SizedBox(height: 10),

            _buildSettingsItem(
              icon: Icons.info_outline,
              title: "Tentang Aplikasi",
              trailing: Text("v1.0.4", style: TextStyle(color: AppColors.textSecondary)),
              onTap: () {
                // Tampilkan About Dialog atau Page
              },
            ),

            _buildSettingsItem(
              icon: Icons.delete_outline,
              title: "Hapus Akun",
              iconColor: AppColors.error,
              textColor: AppColors.error,
              onTap: () => _showDeleteAccountDialog(context, user),
            ),
          ],
        ),
      ),
    );
  }

  // ================= HELPER WIDGETS =================

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    Widget? trailing,
    Color? iconColor,
    Color? textColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6)],
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (iconColor ?? AppColors.primary).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor ?? AppColors.primary, size: 22),
        ),
        title: Text(
          title,
          style: TextStyle(
              color: textColor ?? AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 15
          ),
        ),
        subtitle: subtitle != null
            ? Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textSecondary))
            : null,
        trailing: trailing ?? Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.textSecondary),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildSwitchItem({
    required IconData icon,
    required String title,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6)],
      ),
      child: SwitchListTile(
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.primary, size: 22),
        ),
        title: Text(
          title,
          style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 15
          ),
        ),
        value: value,
        activeColor: AppColors.primary,
        onChanged: onChanged,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ================= DIALOG LOGIC =================

  // 1. Ubah Nama
  void _showEditNameDialog(BuildContext context, User? user) {
    final controller = TextEditingController(text: user?.displayName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Ubah Nama"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: "Nama Lengkap"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                try {
                  // Update Firebase
                  await user?.updateDisplayName(controller.text);

                  // Reload User agar UI update
                  await user?.reload();

                  // Update State Cubit (Penting agar drawer & profile page berubah)
                  if (context.mounted) {
                    context.read<AuthCubit>().checkAuthStatus(); // Panggil fungsi cek status di cubit untuk refresh
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Nama berhasil diperbarui")),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Gagal: $e"), backgroundColor: AppColors.error),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text("Simpan", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  // 2. Ubah Password
  void _showChangePasswordDialog(BuildContext context, User? user) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Ganti Password"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Masukkan password baru Anda. (Minimal 6 karakter)",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Password Baru",
                prefixIcon: Icon(Icons.lock),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.length >= 6) {
                try {
                  await user?.updatePassword(controller.text);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Password berhasil diubah. Silakan login ulang."),
                        backgroundColor: AppColors.success,
                      ),
                    );
                    // Opsional: Logout user setelah ganti password
                    // context.read<AuthCubit>().signOut();
                  }
                } on FirebaseAuthException catch (e) {
                  // Error khusus jika user sudah login terlalu lama
                  if (e.code == 'requires-recent-login') {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Keamanan: Silakan Logout dan Login kembali sebelum mengganti password."),
                        backgroundColor: AppColors.warning,
                        duration: Duration(seconds: 4),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.message ?? "Gagal"), backgroundColor: AppColors.error),
                    );
                  }
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Password minimal 6 karakter"), backgroundColor: AppColors.warning),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text("Simpan", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  // 3. Hapus Akun
  void _showDeleteAccountDialog(BuildContext context, User? user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Hapus Akun?"),
        content: const Text(
          "Tindakan ini permanen dan tidak dapat dibatalkan. Semua data Anda akan hilang.",
          style: TextStyle(color: AppColors.error),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            onPressed: () async {
              try {
                await user?.delete();
                if (context.mounted) {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Close Settings Page
                  // AuthCubit otomatis akan mendeteksi user null dan redirect ke Login Page
                }
              } on FirebaseAuthException catch (e) {
                if (e.code == 'requires-recent-login') {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Keamanan: Silakan Logout dan Login kembali sebelum menghapus akun."),
                      backgroundColor: AppColors.warning,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text("Hapus Permanen", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }
}