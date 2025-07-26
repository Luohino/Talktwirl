# Flutter optimization rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Supabase classes
-keep class io.supabase.** { *; }

# Image picker and media handling
-keep class io.flutter.plugins.imagepicker.** { *; }
-keep class io.flutter.plugins.videoplayer.** { *; }

# Remove debug logging to reduce size
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
    public static *** w(...);
}

# Aggressive optimization for size
-optimizations !code/simplification/arithmetic,!field/*,!class/merging/*
-optimizationpasses 7
-allowaccessmodification
-repackageclasses ''
-dontpreverify

# Remove unused classes and methods
-dontwarn **
-dontnote **

# Generic optimization
-dontusemixedcaseclassnames
-dontskipnonpubliclibraryclasses
-verbose
