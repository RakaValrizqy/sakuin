# Flutter Gradle Plugin sudah menyertakan consumer ProGuard rules bawaan untuk io.flutter.*.
# Jangan pakai `-keep class io.flutter.**` karena memaksa R8 menahan PlayStoreDeferredComponentManager
# yang mereferensikan com.google.android.play.core.* (deferred components tidak dipakai).
-dontwarn com.google.android.play.core.**

# flutter_local_notifications (Gson serialization untuk notifikasi terjadwal)
-keep class com.dexterous.** { *; }

# sqlite3_flutter_libs / JNA / native bindings
-keep class com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.** { *; }
-dontwarn com.sun.jna.**

# local_auth / AndroidX Biometric
-keep class androidx.biometric.** { *; }

# flutter_secure_storage / Tink / EncryptedSharedPreferences
-keep class com.google.crypto.tink.** { *; }
-keep class androidx.security.crypto.** { *; }
-dontwarn com.google.crypto.tink.**
-dontwarn javax.annotation.**
