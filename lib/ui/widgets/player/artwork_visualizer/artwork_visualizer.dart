import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'package:looper_player/core/providers/providers.dart';
import 'package:looper_player/core/utils/artwork_colors.dart';
import 'package:looper_player/features/playback/presentation/providers/playback/playback_notifier.dart';
import 'package:looper_player/features/settings/domain/artwork_visualizer_style.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import 'package:looper_player/ui/widgets/player/player_spectrum.dart';

import 'visualizer_levels.dart';

part 'visualizer_painters.dart';

/// Wraps the Now Playing artwork with a music-reactive effect (the "Artwork
/// visualizer" setting): a glow or spectrum ring around it, a wave or bars
/// over its bottom edge, or the cover gently breathing with the bass.
///
/// Built to stay cheap, like the animated gradient:
/// * only the effect's own small layers repaint (capped at ~30 fps), the
///   artwork itself is never rebuilt - except the breathing scale, which
///   only rebuilds a Transform;
/// * it runs its own raw analysis ([ArtworkVisualizer.analysis]) on the player's PCM feed
///   (shared with the gradient's FFT, one poll): unclipped and unsmoothed,
///   so [VisualizerLevels] can follow the rhythm, then held back by the
///   user's audio sync delay so it lands with what's heard;
/// * the ticker and the PCM subscription only run while the effect is on
///   and visible (tickers enabled, app resumed, animations not disabled,
///   not [suspended]); on pause everything eases out and the ticker stops;
/// * with the effect off it's a plain pass-through: no ticker, no FFT.
///
/// The widget tree is the same for every effect (including none), so
/// switching effects never remounts the artwork.
class ArtworkVisualizer extends ConsumerStatefulWidget {
  final Widget child;

  /// The artwork file, for the "Artwork" colors.
  final String? artPath;

  /// Hide the effect for now (e.g. while the cover is swiped aside).
  final bool suspended;

  final double borderRadius;

  /// Overrides the style from settings (the settings preview).
  final ArtworkVisualizerStyle? style;

  /// Drive the effect from a made-up spectrum that always "plays", instead
  /// of the player - for the settings preview.
  final bool demo;

  const ArtworkVisualizer({
    super.key,
    required this.child,
    this.artPath,
    this.suspended = false,
    this.borderRadius = 12,
    this.style,
    this.demo = false,
  });

  /// The visualizer's own analysis of the player's PCM feed, separate from
  /// the shared FFT preset (which the gradient's calm tuning depends on):
  /// * the full dB range up to 0 dBFS (a full-scale sine reads about
  ///   -6 dB here) - with the plugin's default -30 dB ceiling a loudly
  ///   mastered song's bass sits at max the whole time, so kicks don't
  ///   register;
  /// * no plugin smoothing - its slow release (~0.5 s) kept levels from
  ///   dropping between beats; VisualizerLevels smooths briefly instead;
  /// * 2048 points (23 Hz bins at 48 kHz) so the bass bands each span
  ///   several bins instead of one noisy one, and a 40 Hz floor so the
  ///   lowest band isn't the DC bin.
  static const SpectrumSettings analysis = SpectrumSettings(
    fftSize: 2048,
    bandCount: 16,
    bandLowHz: 40,
    bandHighHz: 16000,
    overlapFactor: 2,
    attackSmoothing: 1,
    releaseSmoothing: 1,
    minDb: -70,
    maxDb: 0,
  );

  @override
  ConsumerState<ArtworkVisualizer> createState() => _ArtworkVisualizerState();
}

class _ArtworkVisualizerState extends ConsumerState<ArtworkVisualizer>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // Capped at ~30 fps: plenty for smoothed levels, half the paint cost.
  static const Duration _paintInterval = Duration(milliseconds: 33);

  late final Ticker _ticker = createTicker(_onTick);
  late final AnimationController _colorAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  late final Listenable _repaint = Listenable.merge([_frame, _colorAnim]);
  final _VisualizerScene _scene = _VisualizerScene();
  final Float32List _demoBands = Float32List(16);
  double _demoSince = 0;

  StreamSubscription<PcmFrame>? _pcmSub;
  BandProcessor _processor = BandProcessor(ArtworkVisualizer.analysis);
  // Analysed frames waiting out the sync delay, oldest first.
  final Queue<_PendingFrame> _pending = Queue<_PendingFrame>();
  final Stopwatch _clock = Stopwatch()..start();
  Duration? _lastFed;
  Duration? _lastElapsed;
  Duration _lastPaint = Duration.zero;

  _ScenePalette? _fromPalette;
  _ScenePalette? _toPalette;
  ArtworkColors? _artColors;
  String? _artColorsPath;
  int _artToken = 0;

  ArtworkVisualizerStyle _style = const ArtworkVisualizerStyle();
  bool _playing = false;
  bool _tickerModeOn = true;
  bool _resumed = true;
  bool _reduceMotion = false;

  bool get _enabled =>
      _style.type != ArtworkVisualizerType.none && !_reduceMotion;

  bool get _active =>
      _enabled && _tickerModeOn && _resumed && !widget.suspended;

  bool get _isPlaying => widget.demo || _playing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _resumed = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (!widget.demo) _listenPlayback();
    _colorAnim.addListener(() {
      _scene.palette = _ScenePalette.lerp(
        _fromPalette!,
        _toPalette!,
        Curves.easeInOut.transform(_colorAnim.value),
      );
    });
  }

  bool _listeningPlayback = false;

  void _listenPlayback() {
    if (_listeningPlayback) return;
    _listeningPlayback = true;
    _playing = ref.read(playbackProvider).isPlaying;
    ref.listenManual(playbackProvider.select((s) => s.isPlaying), (_, playing) {
      _playing = playing;
      _sync();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerModeOn = TickerMode.of(context);
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(covariant ArtworkVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The settings preview switches from its demo to the real audio when a
    // song starts playing.
    if (!widget.demo) _listenPlayback();
    if (oldWidget.suspended != widget.suspended ||
        oldWidget.demo != widget.demo) {
      _sync();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _sync();
  }

  /// Picks the effect colors for the current style and artwork, loading the
  /// artwork's colors when needed. Until they arrive the theme's stay.
  void _updatePalette() {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final _ScenePalette next;
    switch (_style.colors) {
      case ArtworkVisualizerColors.white:
        next = const _ScenePalette(Colors.white, Color(0xFFE6E6E6));
      case ArtworkVisualizerColors.theme:
        next = _ScenePalette(
          readableOnDark(scheme.primary),
          readableOnDark(scheme.tertiary),
        );
      case ArtworkVisualizerColors.artwork:
        // Only extract while the effect is on: it's isolate work per song.
        if (_enabled && _artColorsPath != widget.artPath) _loadArtColors();
        final ArtworkColors? art = _artColors;
        next = art == null
            ? _ScenePalette(
                readableOnDark(scheme.primary),
                readableOnDark(scheme.tertiary),
              )
            : _ScenePalette(
                readableOnDark(art.primary),
                readableOnDark(art.secondary),
              );
    }
    if (_toPalette == null) {
      _fromPalette = _toPalette = _scene.palette = next;
      return;
    }
    if (next == _toPalette) return;
    // Cross-fade from wherever the current fade has got to.
    _fromPalette = _scene.palette;
    _toPalette = next;
    _colorAnim.forward(from: 0);
  }

  Future<void> _loadArtColors() async {
    final String? path = widget.artPath;
    _artColorsPath = path;
    final int token = ++_artToken;
    if (path == null || path.startsWith('http') || !File(path).existsSync()) {
      _artColors = null;
      return;
    }
    try {
      final ArtworkColors? art = await ArtworkColors.fromProvider(
        FileImage(File(path)),
      );
      if (!mounted || token != _artToken) return;
      _artColors = art;
      _updatePalette();
    } catch (_) {
      // Keep the theme colors.
    }
  }

  /// Starts or stops the FFT subscription and the ticker to match what is
  /// actually needed right now.
  void _sync() {
    if (!mounted) return;
    final bool wantAudio = _active && _isPlaying && !widget.demo;
    if (wantAudio && _pcmSub == null) {
      final player = ref.read(audioServiceProvider).player;
      // Sets the shared poll rate (50 ms) the PCM feed arrives at.
      PlayerSpectrum.ensureConfigured(player);
      _pcmSub = player.stream.pcm.listen(_onPcm);
    } else if (!wantAudio && _pcmSub != null) {
      _pcmSub!.cancel();
      _pcmSub = null;
      _pending.clear();
    }

    if (!_active && _scene.levels.reveal > 0) {
      // Hidden: nothing to ease out on screen, so rest at once and come
      // back fading in.
      _scene.levels.clear();
      _pending.clear();
      _processor = BandProcessor(ArtworkVisualizer.analysis);
      _frame.value++;
    }

    final bool wantTick = _active && (_isPlaying || !_scene.levels.settled);
    if (wantTick && !_ticker.isActive) {
      _lastElapsed = null;
      _lastPaint = Duration.zero;
      _ticker.start();
    } else if (!wantTick && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onPcm(PcmFrame pcm) {
    final FftFrame? frame = _processor.process(pcm);
    if (frame == null) return;
    // A burst after a hitch shouldn't pile up; the newest frames matter.
    if (_pending.length > 40) _pending.removeFirst();
    _pending.add(
      _PendingFrame(
        _clock.elapsed + Duration(milliseconds: _style.syncMs),
        Float32List.fromList(frame.bands),
        frame.bandLowHz,
        frame.bandHighHz,
      ),
    );
  }

  /// Feeds the analysed frames whose sync delay is up.
  void _releaseDue() {
    final Duration now = _clock.elapsed;
    while (_pending.isNotEmpty && _pending.first.due <= now) {
      final _PendingFrame f = _pending.removeFirst();
      final Duration? last = _lastFed;
      _lastFed = now;
      final double dt = last == null
          ? 0.05
          : ((now - last).inMicroseconds / 1e6).clamp(0.01, 0.2);
      _scene.levels.addFrame(f.bands, f.lowHz, f.highHz, dt: dt);
    }
  }

  void _onTick(Duration elapsed) {
    final Duration? last = _lastElapsed;
    _lastElapsed = elapsed;
    if (last == null) return;
    // Clamped so a long frame hitch never makes the effect jump.
    final double dt = ((elapsed - last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    final levels = _scene.levels;
    if (widget.demo) {
      _feedDemo(elapsed.inMicroseconds / 1e6, dt);
    } else {
      _releaseDue();
    }
    levels.step(dt, playing: _isPlaying);

    if (elapsed - _lastPaint >= _paintInterval) {
      _lastPaint = elapsed;
      _frame.value++;
    }
    if (!_isPlaying && levels.settled) {
      _frame.value++;
      _sync();
    }
  }

  /// A made-up but music-like spectrum: a bass line thumping at ~2 beats
  /// a second over slowly wandering mids and highs.
  void _feedDemo(double t, double dt) {
    // At the real feed's ~20 frames a second, so onsets look the same.
    _demoSince += dt;
    if (_demoSince < 0.05) return;
    final double frameDt = _demoSince;
    _demoSince = 0;
    final double beat = math
        .pow(0.5 + 0.5 * math.cos(t * 2 * math.pi * 1.9), 6)
        .toDouble();
    for (int i = 0; i < _demoBands.length; i++) {
      final double x = i / (_demoBands.length - 1);
      final double wander = 0.5 + 0.5 * math.sin(t * (1.3 + x * 2.1) + i * 1.7);
      final double v =
          (1 - x) * (0.35 + 0.55 * beat) + x * 0.45 * wander + 0.08;
      _demoBands[i] = (v * (1 - 0.35 * x)).clamp(0.0, 1.0);
    }
    _scene.levels.addFrame(_demoBands, 40, 16000, dt: frameDt);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pcmSub?.cancel();
    _ticker.dispose();
    _colorAnim.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _style =
        widget.style ??
        ref.watch(settingsProvider.select(ArtworkVisualizerStyle.fromSettings));
    _scene
      ..type = _style.type
      ..gain = _style.gain
      ..radius = widget.borderRadius
      ..light = Theme.of(context).brightness == Brightness.light;
    _updatePalette();
    // Start/stop after this frame: _sync can bump the repaint notifier.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());

    final ArtworkVisualizerType type = _enabled
        ? _style.type
        : ArtworkVisualizerType.none;
    final bool hasBack =
        type == ArtworkVisualizerType.aura ||
        type == ArtworkVisualizerType.ring;
    final bool hasFront =
        type == ArtworkVisualizerType.wave ||
        type == ArtworkVisualizerType.bars;

    Widget layer(bool front, bool show) => Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: show && !widget.suspended ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          child: show
              ? RepaintBoundary(
                  child: front
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(
                            widget.borderRadius,
                          ),
                          child: CustomPaint(
                            painter: _VisualizerPainter(
                              scene: _scene,
                              type: type,
                              front: true,
                              repaint: _repaint,
                            ),
                          ),
                        )
                      : CustomPaint(
                          painter: _VisualizerPainter(
                            scene: _scene,
                            type: type,
                            front: false,
                            repaint: _repaint,
                          ),
                        ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        layer(false, hasBack),
        AnimatedBuilder(
          // Only breathing moves the cover; the rest never rebuild it.
          animation: type == ArtworkVisualizerType.breathing
              ? _frame
              : const AlwaysStoppedAnimation<double>(0),
          builder: (context, child) => Transform.scale(
            scale: type == ArtworkVisualizerType.breathing && !widget.suspended
                ? 1 + _scene.breathingScale
                : 1,
            child: child,
          ),
          child: widget.child,
        ),
        layer(true, hasFront),
      ],
    );
  }
}

/// One analysed frame waiting for its [due] time (the sync delay).
class _PendingFrame {
  final Duration due;
  final Float32List bands;
  final double lowHz;
  final double highHz;

  const _PendingFrame(this.due, this.bands, this.lowHz, this.highHz);
}
