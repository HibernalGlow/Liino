package com.looper.player

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.HapticFeedbackConstants
import android.view.View

/**
 * Plays the app's touch haptics at the strength Flutter asks for. The haptic
 * plugins hard-code their pulse strengths, which feel too heavy for taps that
 * repeat all the time, so the tuning lives in Dart (AppHaptics) and this only
 * picks the best way the motor can play it:
 *
 * 1. Scaled primitives (API 30+, where the motor has them) - the crispest.
 * 2. A waveform with per-pulse amplitude.
 * 3. The system's own tick, on motors that can only switch on and off.
 *
 * Everything is tagged as touch feedback, so the system "touch feedback"
 * switch and its intensity slider still apply.
 */
object TouchHaptics {
    private const val TAG_TICK = 0
    private const val TAG_LOW_TICK = 2

    /**
     * Each pulse is [gapMs, durationMs, amplitude (1-255), primitive
     * (0 = tick, 1 = click, 2 = low tick), scale (percent)]. The gap is the
     * pause before the pulse. The low tick is a rounder, lower-pitched tap
     * that only newer motors have; the others play a plain tick instead.
     */
    fun play(context: Context, view: View?, pulses: List<List<Int>>) {
        if (pulses.isEmpty()) return
        val vibrator = vibrator(context)
        if (!vibrator.hasVibrator()) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            vibrator.areAllPrimitivesSupported(
                VibrationEffect.Composition.PRIMITIVE_TICK,
                VibrationEffect.Composition.PRIMITIVE_CLICK,
            )
        ) {
            val hasLowTick = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                vibrator.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_LOW_TICK)
            val composition = VibrationEffect.startComposition()
            for (p in pulses) {
                val primitive = when {
                    p[3] == TAG_LOW_TICK && hasLowTick ->
                        VibrationEffect.Composition.PRIMITIVE_LOW_TICK
                    p[3] == TAG_TICK || p[3] == TAG_LOW_TICK ->
                        VibrationEffect.Composition.PRIMITIVE_TICK
                    else -> VibrationEffect.Composition.PRIMITIVE_CLICK
                }
                composition.addPrimitive(primitive, (p[4] / 100f).coerceIn(0f, 1f), p[0])
            }
            vibrate(vibrator, composition.compose())
            return
        }

        if (vibrator.hasAmplitudeControl()) {
            val timings = ArrayList<Long>()
            val amplitudes = ArrayList<Int>()
            for (p in pulses) {
                if (p[0] > 0) {
                    timings.add(p[0].toLong())
                    amplitudes.add(0)
                }
                timings.add(p[1].toLong())
                amplitudes.add(p[2].coerceIn(1, 255))
            }
            vibrate(
                vibrator,
                VibrationEffect.createWaveform(timings.toLongArray(), amplitudes.toIntArray(), -1),
            )
            return
        }

        // No strength control at all: one system tick is the lightest thing
        // this motor can do, whatever the event was.
        view?.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    }

    private fun vibrator(context: Context): Vibrator =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                .defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }

    private fun vibrate(vibrator: Vibrator, effect: VibrationEffect) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            vibrator.vibrate(
                effect,
                VibrationAttributes.createForUsage(VibrationAttributes.USAGE_TOUCH),
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(
                effect,
                AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .build(),
            )
        }
    }
}
