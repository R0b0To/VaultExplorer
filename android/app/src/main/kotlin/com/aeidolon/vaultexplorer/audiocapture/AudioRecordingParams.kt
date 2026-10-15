package com.aeidolon.vaultexplorer.audiocapture

/**
 * The AAC settings a recording is made with: bitrate and sample rate, both
 * already clamped to values `MediaRecorder` accepts. Always mono -- the
 * recorder captures the microphone as a single channel.
 *
 * The Dart side picks these from the "Audio recording quality" setting and
 * sends them with `start`; [sanitize] is the single place that turns
 * whatever arrived over the channel (nothing, a bad number, a rate the AAC
 * encoder can't take) into something safe, so a bad argument degrades to
 * the default instead of failing the recording.
 */
data class AudioRecordingParams(val bitrate: Int, val sampleRate: Int) {
    companion object {
        const val DEFAULT_BITRATE = 64_000
        const val DEFAULT_SAMPLE_RATE = 44_100
        const val MIN_BITRATE = 16_000
        const val MAX_BITRATE = 192_000

        /** Sample rates a microphone AAC recording can use (the encoder's own list, minus rates above what a mic delivers). */
        val SAMPLE_RATES: Set<Int> = setOf(
            8_000, 11_025, 12_000, 16_000, 22_050, 24_000, 32_000, 44_100, 48_000,
        )

        val DEFAULT = AudioRecordingParams(DEFAULT_BITRATE, DEFAULT_SAMPLE_RATE)

        fun sanitize(bitrate: Int?, sampleRate: Int?): AudioRecordingParams = AudioRecordingParams(
            bitrate = (bitrate ?: DEFAULT_BITRATE).coerceIn(MIN_BITRATE, MAX_BITRATE),
            sampleRate = if (sampleRate != null && sampleRate in SAMPLE_RATES) sampleRate else DEFAULT_SAMPLE_RATE,
        )
    }
}
