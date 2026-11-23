# Keep Flutter & plugin classes safe under R8 shrinking
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# flutter_local_notifications (Gson serialization for scheduled notifications)
-keep class com.dexterous.** { *; }

# sqlite3_flutter_libs / JNA / native bindings
-keep class com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.** { *; }

# local_auth / AndroidX Biometric
-keep class androidx.biometric.** { *; }

# flutter_secure_storage / Tink / EncryptedSharedPreferences
-keep class com.google.crypto.tink.** { *; }
-keep class androidx.security.crypto.** { *; }
