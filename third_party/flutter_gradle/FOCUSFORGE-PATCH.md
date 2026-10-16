# Flutter Android build support

Gradle plugin sources from Flutter 3.50.0-0.1.pre, distributed under
the BSD license in LICENSE. These build-time sources support AGP 9 built-in
Kotlin and the new Android DSL, which Flutter 3.47.6 still accesses through a
removed legacy extension. Only the Gradle build plugin is pinned here; the app
continues to compile and run with the stable Flutter 3.47.6 SDK and engine.

Source release archive SHA-256:
62f0ae902d0feb380e45e257777132c3dd37800278cc69561393bfe2be8da53c
https://storage.googleapis.com/flutter_infra_release/releases/beta/linux/flutter_linux_3.50.0-0.1.pre-beta.tar.xz

Local build-only corrections explicitly retain parameter annotation targets and
remove a redundant null check reported by the Kotlin compiler. Whitespace-only
cleanup removes two upstream trailing spaces. Runtime sources
and dependency validation remain unchanged.

Remove this pinned copy when the stable SDK supports the new DSL. Keep native
unit tests and signed release packaging checks when updating build support.
