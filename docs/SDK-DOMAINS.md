# FocusForge SDK and domain inventory — 2026-11-14

Inventory is source/configuration based. A physical-device and browser network capture was not performed, so upstream SDK-generated endpoints and all request fields are not exhaustively verified. CSP entries indicate allowed domains, not proof of a connection. XML namespace/documentation URLs are not runtime traffic.

The inventory was generated from the resolved dependency graph during the baseline audit. Source line numbers are baseline references; current implementation locations are summarised in SECURITY-HARDENING.md and DATA-INVENTORY.md. The new website account-data endpoint adds authenticated JSON export/deletion and fenced Firestore report writes, without a new third-party SDK or external domain.

## Runtime services and domains

| Domain | Caller / purpose / information | Evidence |
|---|---|---|
| pip-ai-backend.pip-ai-backend.workers.dev | Flutter → Cloudflare: bearer/AppCheck tokens, redacted question/history, numeric study totals; reports also include reason/reply. IP/TLS metadata exists at infrastructure. | focusforge/lib/core/services/ai_backend_service.dart:104 |
| www.focus-forge.in | App legal/deletion pages and branded reset endpoint; Worker authorizes token/quota and drains encrypted reset queue on Vercel. Email submitted only to reset endpoint, not AI. | focusforge/lib/core/services/password_reset_mailer.dart:15; focusforge/pip-ai-backend/src/index.js:235 |
| generativelanguage.googleapis.com | Worker → Gemini: redacted conversation and numeric study summary; provider key header. No Firebase bearer token forwarded to Gemini. | focusforge/pip-ai-backend/src/index.js:90 |
| api.groq.com | Worker → Groq fallback: same minimized content, Groq key header. | focusforge/pip-ai-backend/src/index.js:105 |
| www.googleapis.com | Worker downloads public Firebase JWK signing keys. Google SDK/API endpoints may also use it. | focusforge/pip-ai-backend/src/auth.js:8; focusforge-web/vercel.json:24 |
| identitytoolkit.googleapis.com; securetoken.googleapis.com | Firebase Auth sign-in, credentials/token refresh, email actions. Auth endpoint payload contains credentials/identifiers by design and must be distinguished from model prompts. | focusforge/lib/core/services/firebase_auth_service.dart:280; focusforge-web/src/firebaseClient.ts:22; focusforge-web/vercel.json:24 |
| firestore.googleapis.com | Private profile/level/badges, chosen social sharing, quota/counters/reset encrypted queue. Production database asia-south2 (India). | focusforge/lib/core/services/study_backup_service.dart:241; focusforge-web/vercel.json:24; production-readonly.json |
| firebaseappcheck.googleapis.com; content-firebaseappcheck.googleapis.com | Firebase AppCheck tokens and attestation signals; security telemetry, not marketing analytics. | focusforge/lib/core/services/app_attestation.dart:8; focusforge-web/vercel.json:24 |
| accounts.google.com; apis.google.com | Google OAuth/Sign-In popup/helper requests. Google Play services/Play Integrity can generate additional Google-controlled endpoints. | focusforge/lib/core/services/firebase_auth_service.dart:336; focusforge-web/vercel.json:24 |
| focusforge-1edf7.firebaseapp.com | Firebase authorized OAuth/action helper origin. focusforge-1edf7.web.app, focus-forge.in and focusforgeorg.vercel.app are deployment/authorized aliases, not evidence that the app uploads data to each. | focusforge-web/src/firebaseClient.ts:12; production-readonly.json |
| www.google.com; www.gstatic.com; recaptcha.google.com | Website reCAPTCHA Enterprise scripts/challenges/frames for AppCheck. Standard auth SDK anti-abuse features may also use Google-hosted resources. | focusforge-web/src/firebaseClient.ts:20; focusforge-web/vercel.json:24 |
| lh3.googleusercontent.com | Allowed by website img-src; no dynamic remote image in the inspected app photo path (thumbnail uses local bytes). Allowed domain is not confirmed runtime traffic. | focusforge-web/vercel.json:24; focusforge/lib/core/services/profile_photo.dart:1 |
| smtp.gmail.com:465 | Vercel → Gmail SMTP over TLS: encrypted queued address is decrypted only for delivery; message contains reset link. SMTP credentials server-only. Email HTML references www.focus-forge.in image. | focusforge-web/api/_resetQueue.ts:89; focusforge-web/api/_resetEmail.ts:25 |
| play.google.com; github.com | User-activated store, source and issue links; no automatic study-data upload from these links. GitHub hosts optional source/releases. | focusforge/lib/features/settings/about_screen.dart:22; focusforge-web/src/downloadLinks.ts:2 |
| firebase.google.com; ai.google.dev; groq.com; www.cloudflare.com; docs.github.com; vercel.com | User-activated privacy/terms/support links from the website, not embedded trackers. | focusforge-web/src/App.tsx:526; focusforge-web/src/App.tsx:530; focusforge-web/src/App.tsx:534 |

No runtime external font/audio CDN found: Inter/FocusDial and website Figtree are bundled; audio uses setAsset. No Firebase Analytics, Crashlytics, FCM, ad-network, AAID SDK or Supabase dependency found. No Cloud Storage bucket exists in this project. Firebase Auth/AppCheck and hosting still process technical/security metadata; absence of an analytics SDK is not absence of all data processing.

## Direct Flutter dependencies (runtime)

- `cloud_firestore 5.6.12`
- `cupertino_icons 1.0.9`
- `firebase_app_check 0.3.2+10`
- `firebase_auth 5.7.0`
- `firebase_core 3.15.2`
- `flutter 0.0.0`
- `flutter_localizations 0.0.0`
- `flutter_riverpod 2.6.1`
- `go_router 14.8.1`
- `google_sign_in 6.3.0`
- `http 1.6.0`
- `image 4.12.0`
- `image_picker 1.2.4`
- `intl 0.20.3`
- `just_audio 0.9.46`
- `material_color_utilities 0.13.0`
- `permission_handler 11.4.0`
- `shared_preferences 2.5.6`
- `url_launcher 6.3.3`
- `usage_stats 2.0.1`
- `web 1.1.1`

Flutter SDK/localizations are framework packages; usage_stats is the vendored, restricted Android plugin. Other direct libraries cover local state/navigation, rendering, media, HTTP and device permissions. The complete resolved graph below includes development and platform support packages; not all execute on Android.

## All resolved Flutter packages

| Package | Version | Dependency |
|---|---|---|
| _flutterfire_internals | 1.3.59 | transitive |
| antlr4 | 4.13.2 | transitive |
| archive | 4.5.2 | transitive |
| args | 2.7.0 | transitive |
| async | 2.13.1 | transitive |
| audio_session | 0.1.25 | transitive |
| boolean_selector | 2.1.2 | transitive |
| cel | 0.5.6 | transitive |
| characters | 1.4.1 | transitive |
| clock | 1.1.3 | transitive |
| cloud_firestore | 5.6.12 | direct main |
| cloud_firestore_platform_interface | 6.6.12 | direct dev |
| cloud_firestore_web | 4.4.12 | transitive |
| code_assets | 1.2.1 | transitive |
| collection | 1.19.1 | transitive |
| cross_file | 0.3.5+5 | transitive |
| crypto | 3.0.7 | transitive |
| cupertino_icons | 1.0.9 | direct main |
| equatable | 2.1.0 | transitive |
| fake_async | 1.3.3 | transitive |
| fake_cloud_firestore | 3.1.0 | direct dev |
| fake_firebase_security_rules | 0.5.4 | transitive |
| ffi | 2.2.0 | transitive |
| file | 7.0.1 | transitive |
| file_selector_linux | 0.9.4+1 | transitive |
| file_selector_macos | 0.9.5+1 | transitive |
| file_selector_platform_interface | 2.7.0 | transitive |
| file_selector_windows | 0.9.3+6 | transitive |
| firebase_app_check | 0.3.2+10 | direct main |
| firebase_app_check_platform_interface | 0.1.1+10 | transitive |
| firebase_app_check_web | 0.2.0+14 | transitive |
| firebase_auth | 5.7.0 | direct main |
| firebase_auth_platform_interface | 7.7.3 | transitive |
| firebase_auth_web | 5.15.3 | transitive |
| firebase_core | 3.15.2 | direct main |
| firebase_core_platform_interface | 6.0.3 | direct dev |
| firebase_core_web | 2.24.1 | transitive |
| fixnum | 1.1.1 | transitive |
| flutter | 0.0.0 | direct main |
| flutter_lints | 6.0.0 | direct dev |
| flutter_localizations | 0.0.0 | direct main |
| flutter_plugin_android_lifecycle | 2.0.35 | transitive |
| flutter_riverpod | 2.6.1 | direct main |
| flutter_test | 0.0.0 | direct dev |
| flutter_web_plugins | 0.0.0 | transitive |
| go_router | 14.8.1 | direct main |
| google_identity_services_web | 0.3.3+1 | transitive |
| google_sign_in | 6.3.0 | direct main |
| google_sign_in_android | 6.2.1 | transitive |
| google_sign_in_ios | 5.9.0 | transitive |
| google_sign_in_platform_interface | 2.5.0 | transitive |
| google_sign_in_web | 0.12.4+4 | transitive |
| hooks | 2.0.2 | transitive |
| http | 1.6.0 | direct main |
| http_parser | 4.1.2 | transitive |
| image | 4.12.0 | direct main |
| image_picker | 1.2.4 | direct main |
| image_picker_android | 0.8.13+25 | transitive |
| image_picker_for_web | 3.1.1 | transitive |
| image_picker_ios | 0.8.13+12 | transitive |
| image_picker_linux | 0.2.2 | transitive |
| image_picker_macos | 0.2.2+1 | transitive |
| image_picker_platform_interface | 2.11.2 | transitive |
| image_picker_windows | 0.2.2 | transitive |
| intl | 0.20.3 | direct main |
| jni | 1.1.0 | transitive |
| jni_flutter | 1.0.3 | transitive |
| jni_util | 1.0.0 | transitive |
| just_audio | 0.9.46 | direct main |
| just_audio_platform_interface | 4.6.0 | transitive |
| just_audio_web | 0.4.16 | transitive |
| leak_tracker | 11.0.2 | transitive |
| leak_tracker_flutter_testing | 3.0.10 | transitive |
| leak_tracker_testing | 3.0.2 | transitive |
| lints | 6.1.0 | transitive |
| logger | 2.8.0 | transitive |
| logging | 1.3.0 | transitive |
| matcher | 0.12.20 | transitive |
| material_color_utilities | 0.13.0 | direct main |
| meta | 1.18.3 | transitive |
| mime | 2.1.0 | transitive |
| mock_exceptions | 0.8.2 | transitive |
| more | 4.7.0 | transitive |
| objective_c | 9.5.0 | transitive |
| package_config | 3.0.0 | transitive |
| path | 1.9.1 | transitive |
| path_provider | 2.1.6 | transitive |
| path_provider_android | 2.3.1 | transitive |
| path_provider_foundation | 2.6.0 | transitive |
| path_provider_linux | 2.2.2 | transitive |
| path_provider_platform_interface | 2.1.3 | transitive |
| path_provider_windows | 2.3.0 | transitive |
| permission_handler | 11.4.0 | direct main |
| permission_handler_android | 12.1.0 | transitive |
| permission_handler_apple | 9.6.2 | transitive |
| permission_handler_html | 0.1.4+1 | transitive |
| permission_handler_platform_interface | 4.4.1 | transitive |
| permission_handler_windows | 0.2.2 | transitive |
| platform | 3.2.0 | transitive |
| plugin_platform_interface | 2.1.8 | transitive |
| posix | 6.5.2 | transitive |
| pub_semver | 2.2.1 | transitive |
| quiver | 3.2.2 | transitive |
| record_use | 0.6.0 | transitive |
| riverpod | 2.6.1 | transitive |
| rx | 0.4.0 | transitive |
| rxdart | 0.28.0 | transitive |
| shared_preferences | 2.5.6 | direct main |
| shared_preferences_android | 2.4.28 | transitive |
| shared_preferences_foundation | 2.5.7 | transitive |
| shared_preferences_linux | 2.4.1 | transitive |
| shared_preferences_platform_interface | 2.4.2 | direct dev |
| shared_preferences_web | 2.4.3 | transitive |
| shared_preferences_windows | 2.4.1 | transitive |
| sky_engine | 0.0.0 | transitive |
| source_span | 1.10.2 | transitive |
| stack_trace | 1.12.2 | transitive |
| state_notifier | 1.0.0 | transitive |
| stream_channel | 2.1.4 | transitive |
| string_scanner | 1.4.1 | transitive |
| synchronized | 3.4.2 | transitive |
| term_glyph | 1.2.2 | transitive |
| test_api | 0.7.12 | transitive |
| typed_data | 1.4.0 | transitive |
| url_launcher | 6.3.3 | direct main |
| url_launcher_android | 6.3.33 | transitive |
| url_launcher_ios | 6.4.2 | transitive |
| url_launcher_linux | 3.2.3 | transitive |
| url_launcher_macos | 3.2.6 | transitive |
| url_launcher_platform_interface | 2.3.2 | direct dev |
| url_launcher_web | 2.4.3 | transitive |
| url_launcher_windows | 3.1.6 | transitive |
| usage_stats | 2.0.1 | direct main |
| uuid | 4.6.0 | transitive |
| vector_math | 2.4.0 | transitive |
| vm_service | 15.3.0 | transitive |
| web | 1.1.1 | direct main |
| xdg_directories | 1.1.0 | transitive |
| yaml | 3.1.4 | transitive |

## Native Android resolved Maven graph

| Package | Resolved version |
|---|---|
| androidx.activity:activity | 1.13.0 |
| androidx.activity:activity-ktx | 1.13.0 |
| androidx.annotation:annotation | 1.10.0 |
| androidx.annotation:annotation-experimental | 1.4.1 |
| androidx.annotation:annotation-jvm | 1.10.0 |
| androidx.appcompat:appcompat | 1.1.0 |
| androidx.appcompat:appcompat-resources | 1.1.0 |
| androidx.arch.core:core-common | 2.2.0 |
| androidx.arch.core:core-runtime | 2.2.0 |
| androidx.asynclayoutinflater:asynclayoutinflater | 1.0.0 |
| androidx.browser:browser | 1.9.0 |
| androidx.collection:collection | 1.4.2 |
| androidx.collection:collection-jvm | 1.4.2 |
| androidx.collection:collection-ktx | 1.4.2 |
| androidx.compose.runtime:runtime-annotation | 1.9.0 |
| androidx.compose.runtime:runtime-annotation-android | 1.9.0 |
| androidx.concurrent:concurrent-futures | 1.1.0 |
| androidx.coordinatorlayout:coordinatorlayout | 1.0.0 |
| androidx.core:core | 1.18.0 |
| androidx.core:core-ktx | 1.18.0 |
| androidx.core:core-viewtree | 1.0.0 |
| androidx.credentials:credentials | 1.2.0-rc01 |
| androidx.credentials:credentials-play-services-auth | 1.2.0-rc01 |
| androidx.cursoradapter:cursoradapter | 1.0.0 |
| androidx.customview:customview | 1.1.0 |
| androidx.datastore:datastore | 1.1.7 |
| androidx.datastore:datastore-android | 1.1.7 |
| androidx.datastore:datastore-core | 1.1.7 |
| androidx.datastore:datastore-core-android | 1.1.7 |
| androidx.datastore:datastore-core-okio | 1.1.7 |
| androidx.datastore:datastore-core-okio-jvm | 1.1.7 |
| androidx.datastore:datastore-preferences | 1.1.7 |
| androidx.datastore:datastore-preferences-android | 1.1.7 |
| androidx.datastore:datastore-preferences-core | 1.1.7 |
| androidx.datastore:datastore-preferences-core-android | 1.1.7 |
| androidx.datastore:datastore-preferences-external-protobuf | 1.1.7 |
| androidx.datastore:datastore-preferences-proto | 1.1.7 |
| androidx.documentfile:documentfile | 1.0.0 |
| androidx.drawerlayout:drawerlayout | 1.0.0 |
| androidx.exifinterface:exifinterface | 1.4.2 |
| androidx.fragment:fragment | 1.7.1 |
| androidx.fragment:fragment-ktx | 1.7.1 |
| androidx.interpolator:interpolator | 1.0.0 |
| androidx.legacy:legacy-support-core-ui | 1.0.0 |
| androidx.legacy:legacy-support-core-utils | 1.0.0 |
| androidx.lifecycle:lifecycle-common | 2.7.0 |
| androidx.lifecycle:lifecycle-common-java8 | 2.7.0 |
| androidx.lifecycle:lifecycle-livedata-core | 2.7.0 |
| androidx.lifecycle:lifecycle-livedata-core-ktx | 2.7.0 |
| androidx.lifecycle:lifecycle-process | 2.7.0 |
| androidx.lifecycle:lifecycle-runtime | 2.7.0 |
| androidx.lifecycle:lifecycle-runtime-ktx | 2.7.0 |
| androidx.lifecycle:lifecycle-viewmodel | 2.7.0 |
| androidx.lifecycle:lifecycle-viewmodel-ktx | 2.7.0 |
| androidx.lifecycle:lifecycle-viewmodel-savedstate | 2.7.0 |
| androidx.loader:loader | 1.1.0 |
| androidx.localbroadcastmanager:localbroadcastmanager | 1.0.0 |
| androidx.media3:media3-common | 1.4.1 |
| androidx.media3:media3-container | 1.4.1 |
| androidx.media3:media3-database | 1.4.1 |
| androidx.media3:media3-datasource | 1.4.1 |
| androidx.media3:media3-decoder | 1.4.1 |
| androidx.media3:media3-exoplayer | 1.4.1 |
| androidx.media3:media3-exoplayer-dash | 1.4.1 |
| androidx.media3:media3-exoplayer-hls | 1.4.1 |
| androidx.media3:media3-exoplayer-smoothstreaming | 1.4.1 |
| androidx.media3:media3-extractor | 1.4.1 |
| androidx.media:media | 1.7.0 |
| androidx.navigationevent:navigationevent | 1.0.0 |
| androidx.navigationevent:navigationevent-android | 1.0.0 |
| androidx.preference:preference | 1.2.1 |
| androidx.print:print | 1.0.0 |
| androidx.profileinstaller:profileinstaller | 1.4.0 |
| androidx.recyclerview:recyclerview | 1.0.0 |
| androidx.savedstate:savedstate | 1.2.1 |
| androidx.savedstate:savedstate-ktx | 1.2.1 |
| androidx.slidingpanelayout:slidingpanelayout | 1.2.0 |
| androidx.startup:startup-runtime | 1.1.1 |
| androidx.swiperefreshlayout:swiperefreshlayout | 1.0.0 |
| androidx.tracing:tracing | 1.2.0 |
| androidx.transition:transition | 1.4.1 |
| androidx.vectordrawable:vectordrawable | 1.1.0 |
| androidx.vectordrawable:vectordrawable-animated | 1.1.0 |
| androidx.versionedparcelable:versionedparcelable | 1.1.1 |
| androidx.viewpager:viewpager | 1.0.0 |
| androidx.window.extensions.core:core | 1.0.0 |
| androidx.window:window | 1.2.0 |
| androidx.window:window-java | 1.2.0 |
| com.getkeepsafe.relinker:relinker | 1.4.5 |
| com.google.android.gms:play-services-auth | 21.0.0 |
| com.google.android.gms:play-services-auth-api-phone | 18.0.2 |
| com.google.android.gms:play-services-auth-base | 18.0.10 |
| com.google.android.gms:play-services-base | 18.1.0 |
| com.google.android.gms:play-services-basement | 18.4.0 |
| com.google.android.gms:play-services-fido | 20.1.0 |
| com.google.android.gms:play-services-safetynet | 18.0.0 |
| com.google.android.gms:play-services-tasks | 18.2.0 |
| com.google.android.libraries.identity.googleid:googleid | 1.1.0 |
| com.google.android.play:core-common | 2.0.3 |
| com.google.android.play:integrity | 1.3.0 |
| com.google.android.recaptcha:recaptcha | 18.6.1 |
| com.google.android:annotations | 4.1.1.4 |
| com.google.code.findbugs:jsr305 | 3.0.2 |
| com.google.code.gson:gson | 2.10.1 |
| com.google.errorprone:error_prone_annotations | 2.50.0 |
| com.google.firebase:firebase-annotations | 16.2.0 |
| com.google.firebase:firebase-appcheck | 18.0.0 |
| com.google.firebase:firebase-appcheck-debug | 18.0.0 |
| com.google.firebase:firebase-appcheck-interop | 17.1.0 |
| com.google.firebase:firebase-appcheck-playintegrity | 18.0.0 |
| com.google.firebase:firebase-appcheck-safetynet | 16.1.2 |
| com.google.firebase:firebase-auth | 23.2.1 |
| com.google.firebase:firebase-auth-interop | 20.0.0 |
| com.google.firebase:firebase-bom | 33.16.0 |
| com.google.firebase:firebase-common | 21.0.0 |
| com.google.firebase:firebase-common-ktx | 21.0.0 |
| com.google.firebase:firebase-components | 18.0.0 |
| com.google.firebase:firebase-database-collection | 18.0.1 |
| com.google.firebase:firebase-firestore | 25.1.4 |
| com.google.firebase:protolite-well-known-types | 18.0.1 |
| com.google.guava:failureaccess | 1.0.3 |
| com.google.guava:guava | 33.7.2-android |
| com.google.guava:listenablefuture | 9999.0-empty-to-avoid-conflict-with-guava |
| com.google.j2objc:j2objc-annotations | 3.1 |
| com.google.protobuf:protobuf-javalite | 3.25.5 |
| com.squareup.okio:okio | 3.4.0 |
| com.squareup.okio:okio-jvm | 3.4.0 |
| io.flutter:arm64_v8a_release | 1.0.0-89c39edfdfae2949f6806e4a315c0c08522238b7 |
| io.flutter:armeabi_v7a_release | 1.0.0-89c39edfdfae2949f6806e4a315c0c08522238b7 |
| io.flutter:flutter_embedding_release | 1.0.0-89c39edfdfae2949f6806e4a315c0c08522238b7 |
| io.flutter:x86_64_release | 1.0.0-89c39edfdfae2949f6806e4a315c0c08522238b7 |
| io.grpc:grpc-android | 1.62.2 |
| io.grpc:grpc-api | 1.62.2 |
| io.grpc:grpc-context | 1.62.2 |
| io.grpc:grpc-core | 1.62.2 |
| io.grpc:grpc-okhttp | 1.62.2 |
| io.grpc:grpc-protobuf-lite | 1.62.2 |
| io.grpc:grpc-stub | 1.62.2 |
| io.grpc:grpc-util | 1.62.2 |
| io.perfmark:perfmark-api | 0.26.0 |
| javax.inject:javax.inject | 1 |
| org.codehaus.mojo:animal-sniffer-annotations | 1.23 |
| org.jetbrains.kotlin:kotlin-android-extensions-runtime | 1.9.22 |
| org.jetbrains.kotlin:kotlin-parcelize-runtime | 1.9.22 |
| org.jetbrains.kotlin:kotlin-stdlib | 2.4.10 |
| org.jetbrains.kotlin:kotlin-stdlib-common | 2.4.10 |
| org.jetbrains.kotlin:kotlin-stdlib-jdk7 | 1.8.22 |
| org.jetbrains.kotlin:kotlin-stdlib-jdk8 | 1.8.22 |
| org.jetbrains.kotlinx:kotlinx-coroutines-android | 1.11.0 |
| org.jetbrains.kotlinx:kotlinx-coroutines-bom | 1.11.0 |
| org.jetbrains.kotlinx:kotlinx-coroutines-core | 1.11.0 |
| org.jetbrains.kotlinx:kotlinx-coroutines-core-jvm | 1.11.0 |
| org.jetbrains.kotlinx:kotlinx-coroutines-play-services | 1.11.0 |
| org.jetbrains:annotations | 23.0.0 |
| org.jspecify:jspecify | 1.0.1 |

## focusforge-web direct npm SDKs

- `@vercel/functions ^3.11.1`
- `firebase ^13.0.0`
- `firebase-admin ^13.10.0`
- `nodemailer ^10.5.0`
- `react ^19.1.0`
- `react-dom ^19.1.0`
Full npm lock inventory: `focusforge-web-npm-packages.json` (363 entries, including tooling).

## focusforge/functions direct npm SDKs

- `firebase-admin ^14.5.0`
- `firebase-functions ^7.4.0`
Full npm lock inventory: `focusforge-functions-npm-packages.json` (212 entries, including tooling).

## focusforge/pip-ai-backend direct npm SDKs

No runtime npm packages; Worker uses native Web APIs. Wrangler is deployment tooling.
Full npm lock inventory: `focusforge-pip-ai-backend-npm-packages.json` (91 entries, including tooling).

## Static domain scan

The two coverage JSON files enumerate every literal HTTP(S) host in tracked text, with path:line references. That scan also includes build/test URLs, README images, metadata namespaces, funding links, documentation and package registries. These must not be misrepresented as app network connections.

Runtime validation remaining: capture a release APK on clean install, guest use, consent refusal/acceptance/withdrawal, Google/email sign-in, Pip, reporting, export and deletion; repeat in browser. Verify SDK anti-abuse telemetry, redirects, DNS, cookies and regional routes. Do not weaken TLS verification to perform that validation.
