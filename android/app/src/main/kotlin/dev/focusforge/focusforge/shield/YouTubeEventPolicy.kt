package dev.focusforge.focusforge.shield

/** YouTube swaps player surfaces inside one activity. Listen to subtree
 * changes as well as windows, then debounce before touching the node tree. */
object YouTubeEventPolicy {
    fun accepts(type: Int, changes: Int): Boolean =
        type == 32 || type == 4194304 || (type == 2048 && changes and 1 != 0)
}
