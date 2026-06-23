# Repository Guidelines

## Project Structure & Module Organization

Openreads is a Flutter book-tracking application. Application code lives in `lib/`: organize new work by feature under `lib/ui/`, and keep shared services, themes, and helpers in `lib/core/`. SQLite access is in `lib/database/`. Bundled images, fonts, icons, and locale JSON files belong in `assets/`; add every new runtime asset to the `flutter.assets` section of `pubspec.yaml`. Android-specific code and Gradle configuration are under `android/`. Product documentation and store artwork live in `doc/` and `fastlane/`.

## Build, Test, and Development Commands

- `flutter pub get` installs the pinned Dart and Flutter dependencies.
- `flutter run` launches the app on a connected device or emulator.
- `dart format lib` formats production Dart sources before review.
- `flutter analyze` runs the configured `flutter_lints` static checks.
- `flutter test` runs tests when present.
- `flutter build apk` builds the Android APK; `flutter build appbundle` produces the Play Store bundle.

The CI pipeline builds Android APKs, app bundles, and an unsigned iOS build. Use the Flutter version declared in `.flutter-version` when reproducing CI locally.

## Coding Style & Naming Conventions

Follow standard Dart formatting (two-space indentation) and the lint rules in `analysis_options.yaml`. Use `snake_case.dart` filenames, `PascalCase` types and widgets, and `camelCase` methods, variables, and parameters. Keep widgets focused; place reusable UI pieces in a feature's `widgets/` directory. Prefer existing Bloc/Cubit, theme, localization, and database patterns over parallel abstractions.

## Testing Guidelines

There is currently no committed test suite. Add focused `flutter_test` coverage for new logic or regressions, placing tests under `test/` with names such as `book_repository_test.dart`. Keep tests deterministic: mock network and platform dependencies, and run `flutter test` plus `flutter analyze` before opening a PR.

## Commit & Pull Request Guidelines

Use Angular/Conventional Commit prefixes, for example `feat: add reading goal`, `fix: handle empty ISBN`, or `chore: update dependencies`. Keep commits atomic and descriptions imperative. Open PRs against `master` with a concise summary, linked issue when applicable, test results, and screenshots or recordings for UI changes. Ensure the pipeline passes and request a rebase-and-merge PR.

## Configuration and Translations

Do not commit signing credentials or machine-local configuration. For user-facing strings, update the appropriate JSON files in `assets/translations/`; use Weblate for broader translation work rather than editing unrelated locales.
