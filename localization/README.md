# Bundled device languages

FocusForge follows the phone's ordered language preferences and falls back to English. The app has no language picker or saved locale. Flutter delegates supply reading direction and standard controls; Android resources supply notification, overlay, widget and system-settings copy.

Supported languages: English, Hindi, Bengali, Urdu, Tamil, Telugu, Marathi, Gujarati, Spanish, Portuguese, French, German, Italian, Turkish, Russian, Ukrainian, Arabic, Persian, Indonesian, Malay, Vietnamese, Thai, Korean, Japanese and Simplified Chinese. Chinese regional variants currently use the same Simplified Chinese catalog.

`catalog.json` maps English source keys to English copy. `translations/<language>.json` contains every source key for each other language. The English wording is the lookup key; persisted enum values, subject names, custom plan names, account names and remote content are never translated as storage data. Positional placeholders such as `{0}` are replaced once, so user text cannot become a second format instruction.

To change copy:

1. Update the English key and all 24 translations. Preserve numbered placeholders, product names and technical tokens such as `@handle`.
2. For native copy, add the English source to `native-translation-keys.json`. Keep `android-resource-sources.json` aligned with `android/app/src/main/res/values/strings.xml` for stable Android resource identifiers.
3. Run `python3 tool/generate_localizations.py` from the repository root. This uses only Python's standard library and never contacts a translation service. Commit the source catalogs and generated files together.
4. Run `python3 tool/generate_localizations.py --check` and the localization/display/layout tests. Do not manually format the generated Dart map; the generator owns its format.

Translations were produced with machine assistance and checked for catalog completeness, nonempty values, interpolation slots and selected terminology. They still need native-speaker copy review. Layout tests cover the Home action at narrow widths, large text and RTL, but do not establish visual quality for every screen in every language.
