package com.aeidolon.vaultexplorer.audiocapture

import org.junit.Assert.assertEquals
import org.junit.Test

class AudioRecordingParamsTest {

    @Test
    fun validValuesPassThrough() {
        val p = AudioRecordingParams.sanitize(32_000, 22_050)
        assertEquals(32_000, p.bitrate)
        assertEquals(22_050, p.sampleRate)
    }

    @Test
    fun missingValuesFallBackToTheDefaults() {
        assertEquals(AudioRecordingParams.DEFAULT, AudioRecordingParams.sanitize(null, null))
        assertEquals(AudioRecordingParams.DEFAULT_BITRATE, AudioRecordingParams.sanitize(null, 48_000).bitrate)
        assertEquals(AudioRecordingParams.DEFAULT_SAMPLE_RATE, AudioRecordingParams.sanitize(96_000, null).sampleRate)
    }

    @Test
    fun bitrateIsClamped() {
        assertEquals(AudioRecordingParams.MIN_BITRATE, AudioRecordingParams.sanitize(1, 44_100).bitrate)
        assertEquals(AudioRecordingParams.MIN_BITRATE, AudioRecordingParams.sanitize(-5, 44_100).bitrate)
        assertEquals(AudioRecordingParams.MAX_BITRATE, AudioRecordingParams.sanitize(10_000_000, 44_100).bitrate)
    }

    @Test
    fun qualityNamesResolveToTheirPresets() {
        assertEquals(AudioRecordingParams(32_000, 22_050), AudioRecordingParams.fromQualityName("voice"))
        assertEquals(AudioRecordingParams(64_000, 44_100), AudioRecordingParams.fromQualityName("standard"))
        assertEquals(AudioRecordingParams(128_000, 44_100), AudioRecordingParams.fromQualityName("high"))
    }

    @Test
    fun qualityNamesAreCaseAndWhitespaceInsensitive() {
        assertEquals(AudioRecordingParams.VOICE, AudioRecordingParams.fromQualityName("VOICE"))
        assertEquals(AudioRecordingParams.HIGH, AudioRecordingParams.fromQualityName(" High "))
    }

    @Test
    fun missingOrUnknownQualityNameFallsBackToTheDefault() {
        assertEquals(AudioRecordingParams.DEFAULT, AudioRecordingParams.fromQualityName(null))
        assertEquals(AudioRecordingParams.DEFAULT, AudioRecordingParams.fromQualityName(""))
        assertEquals(AudioRecordingParams.DEFAULT, AudioRecordingParams.fromQualityName("ultra"))
        // The default is the "standard" preset, so the two can't drift apart.
        assertEquals(AudioRecordingParams.STANDARD, AudioRecordingParams.DEFAULT)
    }

    @Test
    fun everyPresetSurvivesSanitizeUnchanged() {
        for (p in listOf(AudioRecordingParams.VOICE, AudioRecordingParams.STANDARD, AudioRecordingParams.HIGH)) {
            assertEquals(p, AudioRecordingParams.sanitize(p.bitrate, p.sampleRate))
        }
    }

    @Test
    fun unsupportedSampleRateFallsBackToTheDefault() {
        assertEquals(AudioRecordingParams.DEFAULT_SAMPLE_RATE, AudioRecordingParams.sanitize(64_000, 12_345).sampleRate)
        // Fine for the AAC encoder in general, but not something a microphone recording uses.
        assertEquals(AudioRecordingParams.DEFAULT_SAMPLE_RATE, AudioRecordingParams.sanitize(64_000, 96_000).sampleRate)
        assertEquals(AudioRecordingParams.DEFAULT_SAMPLE_RATE, AudioRecordingParams.sanitize(64_000, 0).sampleRate)
    }
}
