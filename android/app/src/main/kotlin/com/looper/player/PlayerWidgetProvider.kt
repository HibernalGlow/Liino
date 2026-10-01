package com.looper.player

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.*
import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import android.widget.RemoteViews
import android.util.Log

open class PlayerWidgetProvider : AppWidgetProvider() {

    /** Where a card-style widget's artwork sits, in dp, for a given widget size. */
    private class ArtBox(
        val widthDp: Int,
        val heightDp: Int,
        // Only the right-hand corners are rounded (artwork flush with the card's right edge)
        val roundRightOnly: Boolean = false,
        // Darken the bottom so a title drawn over the artwork stays readable
        val bottomScrim: Boolean = false,
        // Fade the left edge out into the card
        val fadeLeft: Boolean = false
    )

    private class WidgetSpec(
        val layoutId: Int,
        // The original four widgets: black tinted background, accent-coloured
        // play button, small artwork thumbnail.
        val legacy: Boolean = false,
        val hasProgress: Boolean = false,
        val hasLyrics: Boolean = false,
        // Size from the design, used until the launcher reports a real one
        val designWidthDp: Int = 0,
        val designHeightDp: Int = 0,
        val art: ((widthDp: Int, heightDp: Int) -> ArtBox)? = null
    )

    companion object {
        const val ACTION_PLAY_PAUSE = "com.looper.player.ACTION_PLAY_PAUSE"
        const val ACTION_NEXT = "com.looper.player.ACTION_NEXT"
        const val ACTION_PREV = "com.looper.player.ACTION_PREV"
        const val ACTION_SHUFFLE = "com.looper.player.ACTION_SHUFFLE"
        const val ACTION_REPEAT = "com.looper.player.ACTION_REPEAT"

        private const val CARD_RADIUS_DP = 10f
        private const val MAX_ART_SIDE_PX = 720

        val ALL_PROVIDERS: List<Class<out PlayerWidgetProvider>> = listOf(
            PlayerWidgetProvider::class.java,
            PlayerWidgetProviderSquareArtwork::class.java,
            PlayerWidgetProviderSquareProgress::class.java,
            PlayerWidgetProviderLargeLyrics::class.java,
            PlayerWidgetProviderBar::class.java,
            PlayerWidgetProviderMedium::class.java,
            PlayerWidgetProviderLargeArtwork::class.java,
            PlayerWidgetProviderLargeArtworkInfo::class.java,
            PlayerWidgetProviderTallArtwork::class.java,
            PlayerWidgetProviderTallArtworkInfo::class.java,
            PlayerWidgetProviderDial::class.java,
            PlayerWidgetProviderArtworkSide::class.java
        )

        private fun specFor(providerClass: Class<out PlayerWidgetProvider>): WidgetSpec =
            when (providerClass) {
                PlayerWidgetProviderSquareArtwork::class.java ->
                    WidgetSpec(R.layout.player_widget_square_artwork, legacy = true)
                PlayerWidgetProviderSquareProgress::class.java ->
                    WidgetSpec(R.layout.player_widget_square_progress, legacy = true, hasProgress = true)
                PlayerWidgetProviderLargeLyrics::class.java ->
                    WidgetSpec(R.layout.player_widget_large_lyrics, legacy = true, hasLyrics = true)
                PlayerWidgetProviderBar::class.java ->
                    WidgetSpec(R.layout.player_widget_bar, art = { _, _ -> ArtBox(50, 50) })
                PlayerWidgetProviderMedium::class.java ->
                    WidgetSpec(R.layout.player_widget_medium, art = { _, _ -> ArtBox(99, 99) })
                // The artwork fills whatever the fixed-height controls leave over
                PlayerWidgetProviderLargeArtwork::class.java,
                PlayerWidgetProviderLargeArtworkInfo::class.java ->
                    WidgetSpec(
                        if (providerClass == PlayerWidgetProviderLargeArtwork::class.java)
                            R.layout.player_widget_large_artwork
                        else R.layout.player_widget_large_artwork_info,
                        designWidthDp = 347, designHeightDp = 250,
                        art = { w, h -> ArtBox(w - 24, h - 98) }
                    )
                PlayerWidgetProviderTallArtwork::class.java ->
                    WidgetSpec(
                        R.layout.player_widget_tall_artwork,
                        designWidthDp = 169, designHeightDp = 224,
                        art = { w, h -> ArtBox(w - 21, h - 84) }
                    )
                PlayerWidgetProviderTallArtworkInfo::class.java ->
                    WidgetSpec(
                        R.layout.player_widget_tall_artwork_info,
                        designWidthDp = 169, designHeightDp = 224,
                        art = { w, h -> ArtBox(w - 21, h - 137) }
                    )
                PlayerWidgetProviderDial::class.java ->
                    WidgetSpec(
                        R.layout.player_widget_dial, hasProgress = true,
                        art = { _, _ -> ArtBox(156, 152, bottomScrim = true) }
                    )
                PlayerWidgetProviderArtworkSide::class.java ->
                    WidgetSpec(
                        R.layout.player_widget_artwork_side, hasProgress = true,
                        designWidthDp = 347, designHeightDp = 193,
                        art = { _, h -> ArtBox(187, h, roundRightOnly = true, fadeLeft = true) }
                    )
                else -> WidgetSpec(R.layout.player_widget, legacy = true)
            }

        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            providerClass: Class<out PlayerWidgetProvider> = PlayerWidgetProvider::class.java,
            options: Bundle? = null
        ) {
            try {
                val spec = specFor(providerClass)
                val layoutId = spec.layoutId

                // Pre-inflate the layout locally to catch inflation exceptions (e.g. invalid layouts/attributes)
                try {
                    val inflater = context.getSystemService(Context.LAYOUT_INFLATER_SERVICE) as android.view.LayoutInflater
                    inflater.inflate(layoutId, null)
                    Log.d("PlayerWidget", "Pre-inflated layout successfully: ${context.resources.getResourceEntryName(layoutId)}")
                } catch (ie: Exception) {
                    Log.e("PlayerWidget", "CRITICAL: Layout pre-inflation failed for ${context.resources.getResourceEntryName(layoutId)}!", ie)
                }

                val views = RemoteViews(context.packageName, layoutId)
                val prefs = es.antonborri.home_widget.HomeWidgetPlugin.getData(context)

                val title = prefs.getString("title", "No song playing") ?: "No song playing"
                val artist = prefs.getString("artist", "") ?: ""
                val isPlaying = prefs.getBoolean("isPlaying", false)
                val lyrics = prefs.getString("lyrics", "") ?: ""
                val nextLyrics = prefs.getString("nextLyrics", "") ?: ""
                val artPath = prefs.getString("artPath", "") ?: ""
                val accentColor = try {
                    prefs.getInt("accentColor", Color.parseColor("#55DF69"))
                } catch (e: ClassCastException) {
                    try {
                        prefs.getLong("accentColor", Color.parseColor("#55DF69").toLong()).toInt()
                    } catch (e2: Exception) {
                        Color.parseColor("#55DF69")
                    }
                }

                Log.d("PlayerWidget", "PlayerWidgetProvider: updateWidget: provider=${providerClass.simpleName}, id=$appWidgetId, title=$title, artist=$artist, isPlaying=$isPlaying, accentColor=$accentColor")

                if (spec.legacy && layoutId != R.layout.player_widget_square_artwork) {
                    views.setInt(R.id.widget_background_image, "setColorFilter", Color.BLACK)
                }

                // Set song metadata
                views.setTextViewText(R.id.widget_title, title)
                views.setTextViewText(R.id.widget_artist, artist)

                // Set play/pause icon and play container background color
                if (spec.legacy) {
                    views.setImageViewResource(R.id.widget_play_pause, if (isPlaying) R.drawable.ic_pause else R.drawable.ic_play)
                    // Apply accent colors dynamically to the circular background ImageView
                    views.setInt(R.id.widget_play_pause_background, "setColorFilter", accentColor)
                } else {
                    views.setImageViewResource(R.id.widget_play_pause, if (isPlaying) R.drawable.ic_widget_pause else R.drawable.ic_widget_play)
                }

                if (spec.hasProgress) {
                    val position = readLong(prefs, "position")
                    val duration = readLong(prefs, "duration")
                    val progress = if (duration > 0) (position * 100 / duration).toInt().coerceIn(0, 100) else 0
                    views.setProgressBar(R.id.widget_progress, 100, progress, false)
                }

                if (spec.hasLyrics) {
                    views.setTextViewText(R.id.widget_lyric_active, if (lyrics.isNotEmpty()) lyrics else "Lyrics will appear here...")
                    views.setTextViewText(R.id.widget_lyric_next, nextLyrics)
                    views.setViewVisibility(R.id.widget_lyric_next, if (lyrics.isNotEmpty() && nextLyrics.isNotEmpty()) View.VISIBLE else View.GONE)
                }

                val artFile = resolveArtFile(context, artPath)
                val artSpec = spec.art
                if (artSpec == null) {
                    bindLegacyArtwork(views, artFile)
                } else {
                    val (widthDp, heightDp) = widgetSizeDp(
                        context, options ?: appWidgetManager.getAppWidgetOptions(appWidgetId), spec
                    )
                    views.setImageViewBitmap(R.id.widget_artwork, renderArtwork(context, artFile, artSpec(widthDp, heightDp)))
                }

                // Add PendingIntents for clicks
                views.setOnClickPendingIntent(R.id.widget_play_pause_container, getPendingIntent(context, ACTION_PLAY_PAUSE, providerClass))
                views.setOnClickPendingIntent(R.id.widget_next, getPendingIntent(context, ACTION_NEXT, providerClass))
                if (layoutId != R.layout.player_widget_large_lyrics && layoutId != R.layout.player_widget_bar) {
                    views.setOnClickPendingIntent(R.id.widget_prev, getPendingIntent(context, ACTION_PREV, providerClass))
                }

                // Launch app intent when title, artist or artwork is clicked
                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                val launchPendingIntent = PendingIntent.getActivity(
                    context, 0, launchIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                if (layoutId != R.layout.player_widget_large_artwork && layoutId != R.layout.player_widget_tall_artwork) {
                    views.setOnClickPendingIntent(R.id.widget_title, launchPendingIntent)
                    views.setOnClickPendingIntent(R.id.widget_artist, launchPendingIntent)
                }
                views.setOnClickPendingIntent(R.id.widget_artwork, launchPendingIntent)

                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (t: Throwable) {
                Log.e("PlayerWidget", "Error updating widget (id=$appWidgetId, providerClass=${providerClass.simpleName})", t)
            }
        }

        // home_widget stores a Dart int as Int or Long depending on its magnitude
        private fun readLong(prefs: SharedPreferences, key: String): Long {
            return try {
                prefs.getLong(key, 0L)
            } catch (e: ClassCastException) {
                try {
                    prefs.getInt(key, 0).toLong()
                } catch (e2: Exception) {
                    0L
                }
            }
        }

        private fun resolveArtFile(context: Context, artPath: String): java.io.File? {
            Log.d("PlayerWidget", "artwork path: $artPath")
            var cleanPath = artPath.trim()
            if (cleanPath.startsWith("file://")) {
                cleanPath = cleanPath.substring(7)
            } else if (cleanPath.startsWith("file:")) {
                cleanPath = cleanPath.substring(5)
            }
            if (cleanPath.isEmpty()) return null

            var file = java.io.File(cleanPath)
            if (!file.isAbsolute) {
                file = java.io.File(context.filesDir, cleanPath)
            }
            if (!file.exists()) {
                file = java.io.File(context.filesDir, "album_art/" + file.name)
            }
            if (!file.exists()) {
                file = java.io.File(context.filesDir, file.name)
            }

            Log.d("PlayerWidget", "Resolved artPath: ${file.absolutePath}, exists: ${file.exists()}")
            if (!file.exists()) {
                Log.w("PlayerWidget", "Artwork file does not exist at: ${file.absolutePath}")
                return null
            }
            return file
        }

        private fun bindLegacyArtwork(views: RemoteViews, file: java.io.File?) {
            if (file == null) {
                views.setImageViewResource(R.id.widget_artwork, R.mipmap.ic_launcher)
                return
            }
            try {
                val bitmap = decodeSampledBitmapFromFile(file.absolutePath, 128, 128)
                Log.d("PlayerWidget", "decoded bitmap: ${bitmap != null}")
                if (bitmap != null) {
                    val roundedBitmap = getRoundedCornerBitmap(bitmap, 24) // 24px rounding for 128x128
                    views.setImageViewBitmap(R.id.widget_artwork, roundedBitmap)
                } else {
                    Log.w("PlayerWidget", "Bitmap decoding returned null for ${file.absolutePath}")
                    views.setImageViewResource(R.id.widget_artwork, R.mipmap.ic_launcher)
                }
            } catch (e: Exception) {
                Log.e("PlayerWidget", "Error decoding artwork bitmap", e)
                views.setImageViewResource(R.id.widget_artwork, R.mipmap.ic_launcher)
            }
        }

        private fun widgetSizeDp(context: Context, options: Bundle?, spec: WidgetSpec): Pair<Int, Int> {
            // Launchers report a min/max pair: portrait is min width x max height,
            // landscape the other way round.
            val landscape = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
            val width = options?.getInt(
                if (landscape) AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH else AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH
            ) ?: 0
            val height = options?.getInt(
                if (landscape) AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT
            ) ?: 0
            return Pair(
                if (width > 0) width else spec.designWidthDp,
                if (height > 0) height else spec.designHeightDp
            )
        }

        /**
         * Draws the artwork (or a plain placeholder when there is none) at the
         * exact size of its slot, centre-cropped, with the rounded corners baked
         * in: widget layouts can't clip an ImageView on the Android versions
         * this app still supports.
         */
        private fun renderArtwork(context: Context, file: java.io.File?, box: ArtBox): Bitmap {
            val density = context.resources.displayMetrics.density
            var scale = density
            val longestSide = maxOf(box.widthDp, box.heightDp) * density
            if (longestSide > MAX_ART_SIDE_PX) scale = density * MAX_ART_SIDE_PX / longestSide
            val width = (box.widthDp * scale).toInt().coerceAtLeast(1)
            val height = (box.heightDp * scale).toInt().coerceAtLeast(1)

            val content = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(content)
            val source = file?.let {
                try {
                    decodeSampledBitmapFromFile(it.absolutePath, width, height)
                } catch (e: Exception) {
                    Log.e("PlayerWidget", "Error decoding artwork bitmap", e)
                    null
                }
            }
            if (source != null) {
                // Centre-crop
                val fit = maxOf(width.toFloat() / source.width, height.toFloat() / source.height)
                val srcWidth = (width / fit).toInt().coerceAtMost(source.width)
                val srcHeight = (height / fit).toInt().coerceAtMost(source.height)
                val left = (source.width - srcWidth) / 2
                val top = (source.height - srcHeight) / 2
                canvas.drawBitmap(
                    source,
                    Rect(left, top, left + srcWidth, top + srcHeight),
                    Rect(0, 0, width, height),
                    Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
                )
            } else {
                canvas.drawColor(Color.parseColor("#242424"))
            }

            if (box.bottomScrim) {
                val scrim = Paint()
                scrim.shader = LinearGradient(
                    0f, height * 0.4f, 0f, height.toFloat(),
                    Color.TRANSPARENT, Color.parseColor("#D9000000"), Shader.TileMode.CLAMP
                )
                canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), scrim)
            }
            if (box.fadeLeft) {
                val fade = Paint()
                fade.shader = LinearGradient(
                    0f, 0f, width * 0.75f, 0f,
                    Color.TRANSPARENT, Color.BLACK, Shader.TileMode.CLAMP
                )
                fade.xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
                canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), fade)
            }

            val radius = CARD_RADIUS_DP * scale
            val leftRadius = if (box.roundRightOnly) 0f else radius
            val outline = Path()
            outline.addRoundRect(
                RectF(0f, 0f, width.toFloat(), height.toFloat()),
                floatArrayOf(leftRadius, leftRadius, radius, radius, radius, radius, leftRadius, leftRadius),
                Path.Direction.CW
            )
            val output = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            paint.shader = BitmapShader(content, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            Canvas(output).drawPath(outline, paint)
            return output
        }

        private fun decodeSampledBitmapFromFile(path: String, reqWidth: Int, reqHeight: Int): Bitmap? {
            try {
                val options = BitmapFactory.Options().apply {
                    inJustDecodeBounds = true
                }
                BitmapFactory.decodeFile(path, options)

                options.inSampleSize = calculateInSampleSize(options, reqWidth, reqHeight)
                options.inJustDecodeBounds = false
                return BitmapFactory.decodeFile(path, options)
            } catch (e: Exception) {
                return null
            }
        }

        private fun calculateInSampleSize(options: BitmapFactory.Options, reqWidth: Int, reqHeight: Int): Int {
            val height = options.outHeight
            val width = options.outWidth
            var inSampleSize = 1

            if (height > reqHeight || width > reqWidth) {
                val halfHeight = height / 2
                val halfWidth = width / 2
                while (halfHeight / inSampleSize >= reqHeight && halfWidth / inSampleSize >= reqWidth) {
                    inSampleSize *= 2
                }
            }
            return inSampleSize
        }

        private fun getPendingIntent(context: Context, action: String, providerClass: Class<out PlayerWidgetProvider>): PendingIntent {
            val intent = Intent(context, providerClass).apply {
                this.action = action
            }
            return PendingIntent.getBroadcast(
                context, action.hashCode() + providerClass.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun getRoundedCornerBitmap(bitmap: Bitmap, pixels: Int): Bitmap {
            val output = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(output)

            val color = -0xbdbdbe
            val paint = Paint()
            val rect = Rect(0, 0, bitmap.width, bitmap.height)
            val rectF = RectF(rect)
            val roundPx = pixels.toFloat()

            paint.isAntiAlias = true
            canvas.drawARGB(0, 0, 0, 0)
            paint.color = color
            canvas.drawRoundRect(rectF, roundPx, roundPx, paint)

            paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
            canvas.drawBitmap(bitmap, rect, rect, paint)

            return output
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId, javaClass)
        }
        // A widget that was just placed has only whatever was last saved (maybe
        // nothing): have the running app send the current song.
        MainActivity.requestWidgetRefresh()
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: Bundle) {
        updateWidget(context, appWidgetManager, appWidgetId, javaClass, newOptions)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val action = intent.action ?: return

        when (action) {
            ACTION_PLAY_PAUSE -> {
                sendMediaButtonIntent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
            }
            ACTION_NEXT -> {
                sendMediaButtonIntent(context, KeyEvent.KEYCODE_MEDIA_NEXT)
            }
            ACTION_PREV -> {
                sendMediaButtonIntent(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS)
            }
            ACTION_SHUFFLE, ACTION_REPEAT -> {
                MainActivity.sendWidgetAction(context, action)
            }
        }
    }

    private fun sendMediaButtonIntent(context: Context, keycode: Int) {
        // Map keycodes to widget action strings so that MainActivity can
        // route them through the Flutter MethodChannel to PlaybackNotifier.
        // (com.ryanheise.audioservice.MediaButtonReceiver no longer exists
        //  since the migration to mpv_audio_kit.)
        val action = when (keycode) {
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> ACTION_PLAY_PAUSE
            KeyEvent.KEYCODE_MEDIA_NEXT       -> ACTION_NEXT
            KeyEvent.KEYCODE_MEDIA_PREVIOUS   -> ACTION_PREV
            else -> return
        }
        MainActivity.sendWidgetAction(context, action)
    }
}

class PlayerWidgetProviderSquareArtwork : PlayerWidgetProvider()
class PlayerWidgetProviderSquareProgress : PlayerWidgetProvider()
class PlayerWidgetProviderLargeLyrics : PlayerWidgetProvider()
class PlayerWidgetProviderBar : PlayerWidgetProvider()
class PlayerWidgetProviderMedium : PlayerWidgetProvider()
class PlayerWidgetProviderLargeArtwork : PlayerWidgetProvider()
class PlayerWidgetProviderLargeArtworkInfo : PlayerWidgetProvider()
class PlayerWidgetProviderTallArtwork : PlayerWidgetProvider()
class PlayerWidgetProviderTallArtworkInfo : PlayerWidgetProvider()
class PlayerWidgetProviderDial : PlayerWidgetProvider()
class PlayerWidgetProviderArtworkSide : PlayerWidgetProvider()
