import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError('iOS not configured - add iOS app in Firebase Console');
      case TargetPlatform.macOS:
        throw UnsupportedError('macOS not configured');
      case TargetPlatform.windows:
        return web; // Use web config for Windows desktop
      case TargetPlatform.linux:
        throw UnsupportedError('Linux not configured');
      default:
        throw UnsupportedError('Unsupported platform');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyATDO1AtZr0XOzHOnYQ8ZgSptSgxT78RnA',
    appId: '1:694472972526:web:366c99c0d8a6ba8a6ebbff',
    messagingSenderId: '694472972526',
    projectId: 'quickchat-flutter-app',
    authDomain: 'quickchat-flutter-app.firebaseapp.com',
    storageBucket: 'quickchat-flutter-app.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCDN9-RJSk32Dg0-uJckpDG81c_PDiNbVk',
    appId: '1:694472972526:android:d4a3118fbd93fe616ebbff',
    messagingSenderId: '694472972526',
    projectId: 'quickchat-flutter-app',
    storageBucket: 'quickchat-flutter-app.firebasestorage.app',
  );
}
