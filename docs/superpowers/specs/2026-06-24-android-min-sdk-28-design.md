# Android minimum SDK 28

## Goal

Require Android 9 (API level 28) or newer to install Openreads.

## Design

Set `minSdkVersion` to the explicit integer `28` in the Android app module's
`defaultConfig`. Continue inheriting `compileSdk` and `targetSdk` from Flutter.

## Scope

- Change only `android/app/build.gradle`.
- Do not alter the Android Gradle Plugin, Gradle wrapper, Kotlin version,
  compile SDK, or target SDK.
- Do not touch existing uncommitted changes.

## Validation

Run the existing Gradle `printSdkVersions` task and confirm that the reported
minimum SDK is `28`.
