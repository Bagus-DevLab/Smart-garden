import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubit/notification/notification_cubit.dart';

class NotificationDrawer extends StatelessWidget {
  const NotificationDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          const DrawerHeader(
            child: Text(
              'Notifications',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: BlocBuilder<NotificationCubit, dynamic>(
              builder: (context, state) {
                if (state.notifications.isEmpty) {
                  return const Center(
                    child: Text('Belum ada notifikasi'),
                  );
                }

                return ListView.builder(
                  itemCount: state.notifications.length,
                  itemBuilder: (context, index) {
                    final n = state.notifications[index];
                    return ListTile(
                      leading: const Icon(Icons.notifications),
                      title: Text(n.title),
                      subtitle: Text(n.body),
                      trailing: Text(
                        '${n.time.hour}:${n.time.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
