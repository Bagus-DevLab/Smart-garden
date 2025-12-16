// lib/widgets/app_drawer.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_farming/theme/app_colors.dart';
import 'package:smart_farming/cubit/auth/auth_cubit.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surfaceVariant,
      child: BlocBuilder<AuthCubit, AuthState>(
        builder: (context, state) {
          // Get user data
          final user = context.read<AuthCubit>().currentUser;
          final userName = user?.displayName ?? 'Smart Farming User';
          final userEmail = user?.email ?? 'user@smartfarm.id';

          return Column(
            children: [
              // Header with gradient
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.accent,
                      AppColors.primaryDark,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.white,
                          child: user?.photoURL != null
                              ? ClipOval(
                                  child: Image.network(
                                    user!.photoURL!,
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(
                                        Icons.agriculture,
                                        color: AppColors.primary,
                                        size: 40,
                                      );
                                    },
                                  ),
                                )
                              : Icon(
                                  Icons.agriculture,
                                  color: AppColors.primary,
                                  size: 40,
                                ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          userName,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          userEmail,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (user != null && !user.emailVerified)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Email belum terverifikasi',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // Menu Items
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    _DrawerItem(
                        icon: Icons.pest_control,
                        title: 'deteksi hama',
                        onTap: (){
                          // TODO: Navigate to hama page
                          Navigator.pop(context);
                        },
                    ),
                    _DrawerItem(
                      icon: Icons.health_and_safety, 
                      title: 'Status Tanaman', 
                      onTap: () {
                        // TODO: Navigate to status page
                        Navigator.pop(context);
                      },
                      ),
                    _DrawerItem(
                      icon: Icons.person_outline,
                      title: "Profil",
                      onTap: () {
                        // TODO: Navigate to profile
                        Navigator.pop(context);
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.history,
                      title: "Riwayat Data",
                      onTap: () {
                        // TODO: Navigate to history
                        Navigator.pop(context);
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.notifications_outlined,
                      title: "Notifikasi",
                      onTap: () {
                        // TODO: Navigate to notifications
                        Navigator.pop(context);
                      },
                    ),
                    
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Divider(
                        color: AppColors.divider,
                        thickness: 1,
                      ),
                    ),
                    
                    _DrawerItem(
                      icon: Icons.settings_outlined,
                      title: "Pengaturan",
                      onTap: () {
                        // TODO: Navigate to settings
                        Navigator.pop(context);
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.info_outline,
                      title: "Tentang Aplikasi",
                      onTap: () {
                        // TODO: Show about dialog
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),

              // Logout at bottom
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: _DrawerItem(
                  icon: Icons.logout,
                  title: "Logout",
                  iconColor: AppColors.error,
                  textColor: AppColors.error,
                  onTap: () {
                    _showLogoutDialog(context);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceVariant,
          title: Text(
            'Konfirmasi Logout',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Apakah Anda yakin ingin keluar?',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Batal',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext); // Close dialog
                Navigator.pop(context); // Close drawer
                // Call logout from AuthCubit
                context.read<AuthCubit>().signOut();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text('Logout'),
            ),
          ],
        );
      },
    );
  }
}

// Custom Drawer Item Widget
class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? textColor;

  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.iconColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: iconColor ?? AppColors.primary,
        size: 24,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: textColor ?? AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      onTap: onTap,
      hoverColor: AppColors.surface.withOpacity(0.3),
      splashColor: AppColors.primary.withOpacity(0.1),
    );
  }
}