# Bilingual Localization Design

## Goal

Restrict the app UI to English and Simplified Chinese only, remove all other shipped translation files, fill missing Chinese translations for user-visible interface text, then build and validate an `x86_64` APK in the Android emulator.

## Scope

- Keep only `assets/translations/en-US.json` and `assets/translations/zh-CN.json`.
- Restrict the selectable UI languages to English and Chinese.
- Audit user-visible strings that still appear in English when the app is switched to Chinese.
- Add missing localization keys and Chinese translations for those strings.
- Build an `x86_64` APK and verify install + launch in the emulator.

## Non-Goals

- No copywriting overhaul beyond missing or hardcoded UI text needed for Chinese parity.
- No changes to backend/API language behavior such as HTTP `Accept-Language` for external services unless the UI directly depends on it.
- No redesign of the settings or localization architecture.

## Current State

- `assets/translations/` contains many locale JSON files.
- `lib/core/constants/locale.dart` defines a long `supportedLocales` list used by the app settings UI and Easy Localization bootstrap.
- `lib/main.dart` initializes Easy Localization from `supportedLocales`.
- The user reports that even with Chinese selected, multiple screens still show English, which likely means either:
  - missing keys in `zh-CN.json`, or
  - hardcoded English strings in widgets/screens.

## Chosen Approach

Use the smallest end-to-end change set:

1. Remove all non-English/non-Chinese translation assets.
2. Reduce `supportedLocales` to only English and Chinese.
3. Scan `lib/` for user-visible hardcoded English strings and for translation keys missing from `zh-CN.json`.
4. Localize the missing UI text through the existing Easy Localization flow.
5. Build a dedicated `x86_64` APK for emulator testing and validate startup in the Android emulator.

This keeps the existing localization system intact and avoids unnecessary architecture changes.

## Files Expected To Change

- `assets/translations/*.json`
  - Delete all locale files except `en-US.json` and `zh-CN.json`.
  - Update `zh-CN.json` with missing translated strings.
- `lib/core/constants/locale.dart`
  - Restrict supported language list to English and Chinese.
- `lib/generated/locale_keys.g.dart`
  - Regenerate or update if new localization keys are added.
- `lib/ui/**`
  - Replace hardcoded English UI strings with localization keys where needed.
- `pubspec.yaml`
  - No expected functional change unless asset declarations need narrowing; likely unnecessary because directory-level asset loading is already used.

## Validation Plan

- Switch app locale between English and Chinese and verify both remain selectable.
- Confirm removed locale files are no longer shipped in the repository.
- Build `x86_64` APK for emulator use.
- Install and launch the APK in the Android emulator.
- Verify at least the main visible screens involved in the audit show Chinese text instead of leftover English where fixes were applied.

## Risks

- Some English text may come from package-provided widgets or dynamic content, so not every English word in the UI is necessarily localizable from this repo.
- `locale_keys.g.dart` is generated code; if new keys are introduced, regeneration must stay consistent with the project’s existing localization workflow.
- Deleting locale files is safe only if no runtime code depends on enumerating all asset filenames directly; current code suggests locale support is driven by `supportedLocales`, not filesystem discovery.
