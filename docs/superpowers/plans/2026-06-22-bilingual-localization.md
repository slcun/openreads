# Bilingual Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restrict the app to English and Simplified Chinese, fill missing Chinese UI translations, then build and validate an `x86_64` emulator APK.

**Architecture:** Keep the existing Easy Localization setup, reduce the supported locale list to two languages, remove unused translation assets, and localize remaining hardcoded UI strings through the current translation JSON flow. Validation will use a dedicated `x86_64` APK installed into the Android emulator.

**Tech Stack:** Flutter, Easy Localization, Android Gradle, Android Emulator, adb

---

### Task 1: Constrain Locale Surface

**Files:**
- Modify: `lib/core/constants/locale.dart`
- Verify: `lib/main.dart`

- [ ] Reduce `supportedLocales` to only `Locale('en', 'US')` and `Locale('zh', 'CN')`.
- [ ] Confirm `lib/main.dart` still derives `EasyLocalization.supportedLocales` from `supportedLocales` without extra locale-specific logic that would break the two-language setup.

### Task 2: Remove Unused Translation Assets

**Files:**
- Delete: every file under `assets/translations/` except `en-US.json` and `zh-CN.json`

- [ ] Keep only English and Simplified Chinese translation JSON files.
- [ ] Confirm no code enumerates locale asset filenames directly.

### Task 3: Fill Missing Chinese UI Coverage

**Files:**
- Modify: `assets/translations/zh-CN.json`
- Modify: `assets/translations/en-US.json` if new keys are required
- Modify: `lib/ui/**`
- Modify: `lib/generated/locale_keys.g.dart` if new keys are introduced

- [ ] Audit user-visible UI strings that remain hardcoded in English or are missing from Chinese localization.
- [ ] Replace hardcoded UI strings with translation keys using the current Easy Localization pattern.
- [ ] Add the corresponding English and Chinese entries for any new keys.
- [ ] Keep the scope focused on user-visible interface text in the app screens touched by the audit.

### Task 4: Build and Emulator Validation

**Files:**
- Output: `build/app/outputs/flutter-apk/`

- [ ] Build an `x86_64` APK suitable for the Android emulator.
- [ ] Install the APK into the existing `x86_64` emulator.
- [ ] Launch the app and verify it starts successfully.
- [ ] Switch to Chinese and confirm the visible interface reflects the bilingual cleanup.
