package me.jxl.kiosk_satellite

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ProximitySensorTest {
    @Test
    fun px30ReadingsAlternateBetweenFarAndNear() {
        val threshold = proximityNearThreshold(9f, 9f)
        val readings = listOf(1f, 0f, 1f, 0f, 1f, 0f)
        assertEquals(
            listOf(false, true, false, true, false, true),
            readings.map { it < threshold },
        )
    }

    @Test
    fun binarySensorsRecognizeNearAndFarAcrossRanges() {
        for (range in listOf(9f, 5f, 1f, 0.4f)) {
            val threshold = proximityNearThreshold(range, range)
            assertTrue(0f < threshold, "near at range $range")
            assertFalse(range < threshold, "far at range $range")
            assertFalse(1f < threshold, "far flag at range $range")
        }
    }

    @Test
    fun continuousSensorsKeepTheirDistanceRange() {
        val threshold = proximityNearThreshold(5f, 0.1f)
        assertTrue(2f < threshold)
        assertTrue(4.9f < threshold)
        assertFalse(5f < threshold)
        assertFalse(6f < threshold)
    }

    @Test
    fun missingRangeStillDistinguishesBinaryFlags() {
        for (range in listOf(0f, -1f)) {
            val threshold = proximityNearThreshold(range, 0f)
            assertTrue(0f < threshold)
            assertFalse(1f < threshold)
        }
    }

    @Test
    fun rawCountsRisingWithProximityReadAsNear() {
        // NSPanel Pro (#980): range 9, resolution 9, about 50 at rest.
        val c = ProximityClassifier(9f, 9f)
        val rest = listOf(50f, 48f, 49f, 50f, 48f)
        assertEquals(List(rest.size) { false }, rest.map(c::near))
        // A hand waved in from 20 cm and back out again.
        val wave = listOf(53f, 63f, 92f, 150f, 272f, 789f, 531f, 70f, 52f, 49f)
        assertEquals(
            listOf(false, true, true, true, true, true, true, true, false, false),
            wave.map(c::near),
        )
    }

    @Test
    fun rawCountsFollowSlowDriftWithoutTriggering() {
        val c = ProximityClassifier(9f, 9f)
        var value = 1000f
        repeat(2000) {
            value += 0.2f
            assertFalse(c.near(value), "drift at $value")
        }
        assertTrue(c.near(value * 1.4f))
    }

    @Test
    fun rawCountsFirstJumpFromALowRestingLevelIsNear() {
        val c = ProximityClassifier(9f, 9f)
        assertFalse(c.near(5f))
        assertTrue(c.near(150f))
        assertFalse(c.near(6f))
    }

    @Test
    fun px30FlagsKeepTheirDistanceMeaning() {
        val c = ProximityClassifier(9f, 9f)
        assertEquals(
            listOf(false, true, false, true),
            listOf(1f, 0f, 1f, 0f).map(c::near),
        )
    }

    @Test
    fun aFarReadingJustPastTheRangeIsStillADistance() {
        val c = ProximityClassifier(5f, 1f)
        assertEquals(
            listOf(false, true, false),
            listOf(6f, 0f, 6f).map(c::near),
        )
    }
}
