package io.aesms.app.util

import java.text.BreakIterator
import java.util.Locale

object Grapheme {
    fun count(s: String): Int {
        if (s.isEmpty()) return 0
        val it = BreakIterator.getCharacterInstance(Locale.ROOT)
        it.setText(s)
        var count = 0
        var start = it.first()
        var end = it.next()
        while (end != BreakIterator.DONE) {
            count++
            start = end
            end = it.next()
        }
        // silence unused
        @Suppress("UNUSED_EXPRESSION")
        start
        return count
    }
}
