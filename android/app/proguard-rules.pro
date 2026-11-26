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

# FileProvider untuk auto-update APK & foto struk dari cache internal
-keep class androidx.core.content.FileProvider { *; }

# AndroidX Startup, WorkManager, & Room (wajib di R8 Full Mode agar tidak force close saat cold start)
-keep class id.rakavalrizqy.sakuin.UpdateCheckWorker { *; }
-keep class id.rakavalrizqy.sakuin.SakuinNotificationListener { *; }
-keep class androidx.startup.** { *; }
-keep class * implements androidx.startup.Initializer { *; }
-keep class androidx.work.** { *; }
-keep class * extends androidx.work.Worker { *; }
-keep class * extends androidx.work.CoroutineWorker { *; }
-keep class * extends androidx.work.ListenableWorker { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class androidx.room.** { *; }
-keep class androidx.sqlite.** { *; }
-dontwarn androidx.work.**
-dontwarn androidx.room.**

# Google ML Kit Text Recognition & Firebase Component Discovery (wajib di R8 Full Mode saat cold start)
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.firebase.components.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
-keep class com.google.android.datatransport.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**
-dontwarn com.google.firebase.**
-dontwarn com.google.android.datatransport.**
