import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    throw UnsupportedError('רק Web נתמך כרגע');
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCFPbVkPqv_P_enQ0pOGFX-Y5kQHo14ybk',
    appId: '1:657772973749:web:dcd3ed393632c65d09f8fc',
    messagingSenderId: '657772973749',
    projectId: 'gps-drivers-katarina-243f5',
    authDomain: 'gps-drivers-katarina-243f5.firebaseapp.com',
    storageBucket: 'gps-drivers-katarina-243f5.firebasestorage.app',
  );
}
