import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:smart_farming/cubit/navigation_cubit.dart';
import 'package:smart_farming/pages/pest_detection_page.dart';
import 'package:smart_farming/pages/plant_page.dart';
import 'package:smart_farming/widgets/app_drawer.dart';
import 'package:smart_farming/theme/app_colors.dart';
import 'package:smart_farming/pages/dashboard.dart';
import 'package:smart_farming/pages/irrigation_page.dart';


class BottomNavBar extends StatelessWidget {
  const BottomNavBar({super.key});

  static final List<Widget> pages = [
    const Dashboard(),
    const IrrigationPage(),
    const PlantHealthPage(),
   const PestDetectionPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NavigationCubit, int>(
      builder: (context, pageIndex) {
        return Scaffold(
          backgroundColor: AppColors.background,

          appBar: AppBar(
            title: const Text(
              "Smart Farming",
              style: TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            elevation: 0,
            shadowColor: AppColors.shadow,
          ),

          drawer: const AppDrawer(),

          bottomNavigationBar: CurvedNavigationBar(
            index: pageIndex,
            height: 60,
            items: const [
              Icon(Icons.dashboard, size: 28, color: Colors.white),
              Icon(Icons.water_drop, size: 28, color: Colors.white),
              Icon(Icons.health_and_safety, size: 28, color: Colors.white),
              Icon(Icons.pest_control, size: 28, color: Colors.white),
            ],
            color: AppColors.primary,
            buttonBackgroundColor: AppColors.accent,
            backgroundColor: AppColors.background,
            animationCurve: Curves.easeInOutCubic,
            animationDuration: const Duration(milliseconds: 350),
            onTap: (index) {
              context.read<NavigationCubit>().changeIndex(index);
            },
          ),

          body: pages[pageIndex],
        );
      },
    );
  }
}