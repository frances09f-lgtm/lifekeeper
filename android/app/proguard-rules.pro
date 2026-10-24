-keep class io.flutter.plugins.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.ambi.lifekeeper.SystemReceiver { *; }
# The ML Kit Flutter plugin references optional non-Latin recognizer classes.
# LifeKeeper bundles only the Latin recognizer, so these are never loaded.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
