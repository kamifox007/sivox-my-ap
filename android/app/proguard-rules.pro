# Flutter Wrapper and Engine rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.provider.** { *; }
-keep class class_index_store.** { *; }

# Keep native methods and callbacks
-keepclasseswithmembernames class * {
    native <methods>;
}

# Preserve generated Flutter plugins
-keep class com.sifo.app.standard.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep Firebase and Google Play Services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Security: Strip out Android debug logs in release builds to prevent info leakage
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
    public static int i(...);
}

# Keep standard models
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Keep com.google.android.play.core classes to avoid missing class errors in R8 minification
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**
