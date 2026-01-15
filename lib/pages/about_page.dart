import 'package:flutter/material.dart';
import 'package:smart_farming/theme/app_colors.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceVariant,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceVariant,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Tentang Aplikasi",
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // ================= LOGO & VERSI =================
            // ... (Bagian ini tidak berubah) ...
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.agriculture_rounded,
                size: 60,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "Smart Farming",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                "Versi 1.0.4 (Beta)",
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),

            const SizedBox(height: 40),

            // ================= DESKRIPSI =================
            // ... (Bagian ini tidak berubah) ...
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    "Misi Kami",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Smart Farming hadir untuk membantu petani Indonesia meningkatkan hasil panen melalui teknologi IoT dan AI yang terintegrasi. Memantau lahan, mengontrol irigasi, dan memprediksi cuaca kini ada dalam genggaman.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.5,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ================= PENGEMBANG =================
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 8, bottom: 12),
                child: Text(
                  "Tim Pengembang",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            // === UPDATE PENTING DI SINI ===
            // Pastikan path string di parameter ketiga sesuai dengan nama file yang Anda buat di Langkah 1.
            // Saya menggunakan contoh path 'assets/images/developers/nama_file.jpg'
            _buildDeveloperCard("Bagus Ardiansyah", "Agrisky Lead Developer", "assets/dev/dev1,jpg"),
            _buildDeveloperCard("Aditya Yudha Prastya", "Pest Lead Developer", "assets/images/developers/foto_aditya.jpg"),
            _buildDeveloperCard("Restu Aleksa", "Hyper H Lead Developer", "assets/images/developers/foto_restu.jpg"),
            _buildDeveloperCard("Muhammad Ramadanil", "Irrigation Lead Developer", "assets/images/developers/foto_ramadanil.jpg"),
            _buildDeveloperCard("Septa Rafli Yulio", "Pembajakan Lead Developer", "assets/images/developers/foto_septa.jpg"),

            const SizedBox(height: 24),

            // ================= LEGAL & LAINNYA =================
            // ... (Bagian ini tidak berubah) ...
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 8, bottom: 12),
                child: Text(
                  "Legal & Informasi",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            _buildInfoTile(
              context,
              icon: Icons.privacy_tip_outlined,
              title: "Kebijakan Privasi",
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Membuka Kebijakan Privasi...")),
                );
              },
            ),
            _buildInfoTile(
              context,
              icon: Icons.description_outlined,
              title: "Syarat & Ketentuan",
              onTap: () {},
            ),
            _buildInfoTile(
              context,
              icon: Icons.code_rounded,
              title: "Lisensi Open Source",
              onTap: () {
                showLicensePage(
                  context: context,
                  applicationName: "Smart Farming",
                  applicationVersion: "1.0.0",
                  applicationIcon: const Icon(Icons.agriculture),
                );
              },
            ),

            const SizedBox(height: 40),

            // ================= COPYRIGHT =================
            Text(
              "© 2024 Smart Farming Indonesia\nDibuat dengan ❤️ untuk Petani",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ================= WIDGET YANG DIPERBARUI =================
  Widget _buildDeveloperCard(String name, String role, String assetImagePath) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 5,
          ),
        ],
      ),
      child: Row(
        children: [
          // === UPDATE PENTING DI SINI ===
          CircleAvatar(
            radius: 25, // Ukuran sedikit diperbesar agar foto lebih jelas
            backgroundColor: AppColors.primary.withOpacity(0.1),
            // Menggunakan AssetImage untuk memuat foto dari path yang diberikan
            backgroundImage: AssetImage(assetImagePath),
            // Tambahan opsional: Jika foto gagal dimuat (misal salah path),
            // akan menampilkan inisial sebagai cadangan.
            onBackgroundImageError: (exception, stackTrace) {
              debugPrint("Gagal memuat gambar untuk $name: $exception");
            },
            // Child di bawah ini hanya akan muncul jika gambar gagal dimuat (berkat onBackgroundImageError)
            child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : "?",
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)
            ),
          ),
          // === AKHIR UPDATE ===

          const SizedBox(width: 16),
          Expanded( // Gunakan Expanded agar teks tidak overflow jika nama terlalu panjang
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  role,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    // ... (Bagian ini tidak berubah) ...
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.textSecondary),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textSecondary),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}