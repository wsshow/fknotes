# google_mlkit_text_recognition supports optional script packages through one
# shared bridge. FK Notes only bundles Latin and Chinese recognition models.
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions

# Firebase component discovery instantiates ML Kit registrars by reflection
# from AndroidManifest metadata. R8 cannot see that constructor call and may
# remove the public no-argument constructors in optimized release builds.
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    public <init>();
}
