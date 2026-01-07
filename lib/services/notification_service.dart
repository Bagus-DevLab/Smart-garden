import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubit/notification/notification_cubit.dart';

class NotificationService {
  static void initFCMListeners(NotificationCubit cubit) {
    FirebaseMessaging.onMessage.listen((message) {
      cubit.addFromFCM(message);
    });
  }
}
