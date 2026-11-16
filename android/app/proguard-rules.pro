# Keep MeshOverlayActivity and all its static fields and methods for reflection by M3xMeshContentProvider
-keep class page.puzzak.geminilocal.MeshOverlayActivity { *; }
-keepclassmembers class page.puzzak.geminilocal.MeshOverlayActivity { *; }
-keepclassmembers class page.puzzak.geminilocal.MeshOverlayActivity$* { *; }

# Keep FlutterLocalAiPlugin methods invoked via reflection (e.g. from PaiosVoiceInteractionSession)
-keep class page.puzzak.geminilocal.FlutterLocalAiPlugin { *; }
-keepclassmembers class page.puzzak.geminilocal.FlutterLocalAiPlugin { *; }

# Firebase Crashlytics: preserve source file names, line numbers, annotations, and generic signatures
-keepattributes SourceFile,LineNumberTable
-keepattributes *Annotation*,Signature

# Gson & JSON serialization models (used transitively by Firebase / Google Play Services / ML Kit)
-keep class com.google.gson.** { *; }
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# ML Kit GenAI Prompt / AICore client interfaces and data models
-keep class com.google.mlkit.genai.** { *; }
-keep class com.google.android.apps.aicore.** { *; }
-dontwarn com.google.android.apps.aicore.**

