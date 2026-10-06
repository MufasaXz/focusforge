package dev.focusforge.focusforge.shield

/**
 * The one-way pipe from the accessibility service to Dart.
 *
 * The service runs whether or not the Flutter engine is alive — it has to, or
 * blocking would stop the moment the user swiped the app away. That means
 * every interception it reports may have nobody listening. Rather than drop
 * those on the floor, they queue, and the bridge drains the queue when it
 * attaches.
 *
 * The queue is bounded and old events are discarded first: this feeds an
 * impulse chart, and a chart is not worth unbounded memory.
 */
object ShieldEvents {
    /** The user took the offered way out. */
    const val WALKED_AWAY = "walkedAway"

    /** The user chose to open the app anyway. */
    const val OPENED_ANYWAY = "openedAnyway"

    private const val MAX_PENDING = 50

    private val pending = ArrayDeque<Map<String, Any>>()

    @Volatile
    private var sink: ((Map<String, Any>) -> Unit)? = null

    fun emit(packageName: String, label: String, action: String) {
        val event = mapOf(
            "package" to packageName,
            "name" to label,
            "action" to action,
            "at" to System.currentTimeMillis(),
        )

        val live = sink
        if (live != null) {
            live(event)
            return
        }
        synchronized(pending) {
            if (pending.size >= MAX_PENDING) pending.removeFirst()
            pending.addLast(event)
        }
    }

    /** Hands the queue over and switches to live delivery. */
    fun attach(listener: (Map<String, Any>) -> Unit) {
        sink = listener
        val drained = synchronized(pending) {
            val copy = pending.toList()
            pending.clear()
            copy
        }
        for (event in drained) listener(event)
    }

    fun detach() {
        sink = null
    }
}
