# Built-in Kotlin Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Openreads on Flutter 3.44.2 without the legacy Kotlin Gradle Plugin compatibility mode.

**Architecture:** First align repository toolchain declarations and direct Android-plugin constraints with the verified Flutter 3.44.2 baseline. Then migrate the application module to Built-in Kotlin and use the build warning output as the authoritative list of any remaining plugin blockers. Preserve application behavior; only adapt Dart call sites when a selected package major version requires it.

**Tech Stack:** Flutter 3.44.2, Dart 3.12.2, Gradle 9.6.0, Android Gradle Plugin 9.2.0, Kotlin Built-in Kotlin DSL.

---

### Task 1: Align the repository toolchain contract

**Files:**
- Modify: `.flutter-version:1`
- Modify: `pubspec.yaml:8-10`

- [ ] **Step 1: Set the repository Flutter version**

Replace the single `.flutter-version` value with:

```text
3.44.2
```

- [ ] **Step 2: Set matching Dart and Flutter constraints**

Replace the environment block with:

```yaml
environment:
  sdk: ">=3.12.0 <4.0.0"
  flutter: ">=3.44.2"
```

- [ ] **Step 3: Resolve without changing product code**

Run: `flutter pub get`

Expected: exit code 0 and an updated `pubspec.lock` resolved by Flutter 3.44.2.

### Task 2: Upgrade direct Android-plugin dependencies

**Files:**
- Modify: `pubspec.yaml:48-69`
- Modify: `pubspec.lock`
- Test: `flutter analyze`

- [ ] **Step 1: Set candidate constraints with known current releases**

Set these direct dependency constraints:

```yaml
device_info_plus: ^13.1.0
package_info_plus: ^10.1.0
share_plus: ^13.1.0
shared_preferences: ^2.5.5
saf_stream: ^3.0.0
saf_util: ^3.1.0
```

Keep `dynamic_color`, `barcode_scan2`, and the Git-based `blurhash` constraint
unchanged until a Build-in Kotlin build identifies whether they remain blockers.

- [ ] **Step 2: Resolve the selected upgrade batch**

Run: `flutter pub get`

Expected: exit code 0; the resolved lockfile includes the requested direct
versions or a compatible newer patch release.

- [ ] **Step 3: Correct only source-level API incompatibilities**

Run: `flutter analyze`

Expected: no analysis errors. For each error introduced by the selected
dependency upgrades, update the directly reported call site and re-run
`flutter analyze` until it is clean.

### Task 3: Enable Built-in Kotlin in the application module

**Files:**
- Modify: `android/app/build.gradle:1-42`
- Modify: `android/settings.gradle:26-30`
- Modify: `android/gradle.properties:1-6`

- [ ] **Step 1: Remove the legacy application KGP integration**

In `android/app/build.gradle`, remove:

```groovy
id "kotlin-android"
```

and remove this block from `android {}`:

```groovy
kotlinOptions {
    jvmTarget = JavaVersion.VERSION_17
}
```

- [ ] **Step 2: Configure the Built-in Kotlin compiler target**

Add this top-level block after `android { ... }`:

```groovy
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
```

- [ ] **Step 3: Remove project-level compatibility switches**

Delete these lines from `android/gradle.properties`:

```properties
android.builtInKotlin=false
android.newDsl=false
```

Remove the unused `org.jetbrains.kotlin.android` plugin declaration from
`android/settings.gradle` when no build script applies it.

- [ ] **Step 4: Inspect resolved Build-in Kotlin status**

Run: `cmd /c gradlew.bat printSdkVersions --no-daemon` from `android/`.

Expected: exit code 0, `minSdkVersion` API 28, and no warning that the app
module itself applies the Kotlin Gradle Plugin.

### Task 4: Resolve remaining Android plugin blockers

**Files:**
- Modify: `pubspec.yaml` only if a plugin upgrade or replacement is required
- Modify: `pubspec.lock`
- Modify: direct Dart import and call sites only if replacing a package

- [ ] **Step 1: Identify the remaining blockers from a real APK build**

Run: `flutter build apk --target-platform android-arm64`

Expected: either a successful build without KGP warnings, or a precise list of
plugins still applying KGP.

- [ ] **Step 2: Apply the narrowest compatible resolution for each blocker**

Use this priority order: upgrade to an upstream Built-in Kotlin release, replace
an unmaintained package with a compatible maintained package, then use a
repository-local fork only when replacement would alter user-visible behavior.

- [ ] **Step 3: Rebuild after each blocker resolution**

Run: `flutter build apk --target-platform android-arm64`

Expected: the KGP warning list shrinks after each resolution and is empty at
completion.

### Task 5: Final verification

**Files:**
- Test: Android Gradle and Flutter build output

- [ ] **Step 1: Run static analysis**

Run: `flutter analyze`

Expected: exit code 0 with no analysis errors.

- [ ] **Step 2: Build the delivery ABI**

Run: `flutter build apk --target-platform android-arm64`

Expected: exit code 0; generated APK supports Android 9+ ARM64 devices.

- [ ] **Step 3: Perform Android feature smoke checks**

On an Android device or emulator, manually confirm barcode scanning, backup
export/import through SAF, and sharing an export. These cover the plugins most
likely to need source migration.
