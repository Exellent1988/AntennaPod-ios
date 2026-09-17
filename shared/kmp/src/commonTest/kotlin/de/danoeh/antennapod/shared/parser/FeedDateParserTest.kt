package de.danoeh.antennapod.shared.parser

import kotlin.test.Test
import kotlin.test.assertEquals

class FeedDateParserTest {
    @Test
    fun parsesIsoUtc() {
        assertEquals(0L, FeedDateParser.parseToEpochMs("1970-01-01T00:00:00Z"))
        assertEquals(60_000L, FeedDateParser.parseToEpochMs("1970-01-01T00:01:00Z"))
    }

    @Test
    fun parsesRfc822WithOffset() {
        assertEquals(0L, FeedDateParser.parseToEpochMs("01 Jan 70 01:00:00 +0100"))
        assertEquals(60_000L, FeedDateParser.parseToEpochMs("01 Jan 70 01:01:00 +0100"))
    }
}
