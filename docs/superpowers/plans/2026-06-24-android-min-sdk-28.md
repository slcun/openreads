# Android Minimum SDK 28 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Require Android 9 (API level 28) or later to install Openreads.

**Architecture:** Set an explicit `minSdkVersion` in the Android application module. Keep the existing Flutter-provided compile and target SDK values unchanged, so this adjustment affects installation eligibility only.

**Tech Stack:** Flutter Android Gradle plugin, Gradle Groovy DSL.

---

### Task 1: Set the app's minimum Android API level

**Files:**
- Modify: `android/app/build.gradle:51`
- Test: Gradle task `printSdkVersions` in `android/app/build.gradle:86-92`

- [ ] **Step 1: Confirm the current source setting**

Run: `rg -n "minSdkVersion" android/app/build.gradle`

Expected: the app module inherits `flutter.minSdkVersion`.

- [ ] **Step 2: Set an explicit installation floor**

Replace this line in `defaultConfig`:

```groovy
minSdkVersion flutter.minSdkVersion
```

with:

```groovy
minSdkVersion 28
```

- [ ] **Step 3: Verify the resolved Android SDK configuration**

Run: `cmd /c gradlew.bat printSdkVersions --no-daemon` from `android/`.

Expected: exit code 0 and `The current minSdkVersion is: 28`. The output must
also show existing compile and target SDK values without changing them.

- [ ] **Step 4: Check the final diff**

Run: `git diff --check -- android/app/build.gradle` and
`git diff -- android/app/build.gradle`.

Expected: no whitespace errors and a one-line production configuration change.
