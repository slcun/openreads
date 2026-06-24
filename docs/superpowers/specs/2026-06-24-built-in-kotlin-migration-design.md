# Built-in Kotlin migration

## Goal

Make the Android build compatible with Flutter's Built-in Kotlin mode, so a
future Flutter release can build the application without the legacy Kotlin
Gradle Plugin compatibility layer.

## Baseline

The repository will require Flutter 3.44.2 and Dart 3.12.2, matching the
installed stable toolchain. Android continues to use AGP 9.2.0, Gradle 9.6.0,
Java 17, compile SDK 36, target SDK 36, and minimum SDK 28.

## Migration sequence

1. Update the repository's Flutter and Dart version declarations.
2. Upgrade dependencies in a controlled batch, then resolve source-level API
   changes and Android build compatibility.
3. Verify which remaining Android plugins still apply the legacy KGP. Replace,
   upgrade, or minimally fork only the plugins that block Built-in Kotlin.
4. Migrate the application Android module: remove `kotlin-android` and the old
   `kotlinOptions` block, configure the Kotlin compiler through the Built-in
   Kotlin DSL, and remove the two Flutter compatibility switches.
5. Verify analysis and Android APK builds. Exercise barcode scanning, backup
   import/export, and sharing on Android because their plugins are migration
   risks.

## Scope

- Keep the existing product behavior and Android SDK levels unchanged.
- Do not modify the globally installed Flutter SDK.
- Preserve unrelated uncommitted changes.

## Completion criteria

- Flutter's build output no longer reports the application or its resolved
  Android plugins as applying the Kotlin Gradle Plugin.
- `flutter analyze` and an Android ARM64 APK build succeed on Flutter 3.44.2.
