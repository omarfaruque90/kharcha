# google_mlkit_text_recognition references optional script-specific recognizer
# option classes (Chinese / Japanese / Korean / Devanagari) that are NOT
# bundled with the default Latin recognizer. They are only used when the
# corresponding script models are requested, so silence R8's missing-class
# errors for them instead of bundling extra models.
-dontwarn com.google.mlkit.vision.text.**
-keep class com.google.mlkit.vision.text.TextRecognizer { *; }
