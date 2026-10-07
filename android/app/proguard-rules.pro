# R8 keeps classes named in the manifest by itself; these are the ones reached
# in ways it cannot see.

# The accessibility service brings the user back to the app by name, so
# MainActivity has to survive R8 with that name.
-keep class dev.focusforge.focusforge.MainActivity { *; }
