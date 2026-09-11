# R8 缺类放行：google_mlkit_text_recognition 的通用 TextRecognizer 代码引用了
# 各语种脚本识别器（中文/日文/韩文/天城文），本项目仅使用中文脚本，
# 这些类在运行时不会被触达，忽略缺类告警即可。
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
