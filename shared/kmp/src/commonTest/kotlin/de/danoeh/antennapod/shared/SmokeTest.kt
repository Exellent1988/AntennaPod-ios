package de.danoeh.antennapod.shared

import kotlin.test.Test
import kotlin.test.assertEquals

class SmokeTest {
    @Test
    fun versionIsSet() {
        assertEquals("0.1.0-SNAPSHOT", AntennaPodShared.VERSION)
    }
}
