# R8 rules for release builds.
#
# `isMinifyEnabled = true` with no rules file means R8 keeps Flutter's own
# defaults and nothing else. Firebase Messaging and OneSignal are reached
# reflectively from the Android runtime, so without these keeps a release build
# can crash on start-up in a way a debug build never reproduces — the classic
# "works on my machine" release bug.

# --- Firebase Cloud Messaging ------------------------------------------------
-keep class com.google.firebase.messaging.** { *; }
-keep class com.google.firebase.iid.** { *; }
-dontwarn com.google.firebase.**
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# `FirebaseMessagingService` is looked up by name from the manifest.
-keep class * extends com.google.firebase.messaging.FirebaseMessagingService {
    <init>(...);
    public *;
}

# --- OneSignal ---------------------------------------------------------------
-keep class com.onesignal.** { *; }
-dontwarn com.onesignal.**

# --- Flutter plugins that register via reflection ----------------------------
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }

# flutter_secure_storage uses the Android Keystore through JNI-adjacent APIs.
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Keep the annotation that Gson-style serialisers look for, if any is added later.
-keep @interface com.google.gson.annotations.** { *; }
-dontwarn com.google.gson.**
