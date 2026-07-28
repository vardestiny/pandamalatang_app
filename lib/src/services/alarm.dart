import 'package:audioplayers/audioplayers.dart';

/// The noise.
///
/// The whole app exists because an email and a silent 20-second refresh let
/// orders be missed, so this is the part that must not be clever. It loops, it is
/// loud, and it ignores the iOS silent switch — a mute toggle nobody remembers
/// flicking must not be able to disable the shop's order alarm.
class Alarm {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  bool _escalated = false;

  Future<void> _configure() async {
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          // Playback, not ambient: ambient respects the silent switch.
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.duckOthers},
        ),
        android: AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          // Alarm, not notification: Android gives alarm streams their own volume
          // and does not silence them under Do Not Disturb.
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      ),
    );
  }

  Future<void> start() async {
    if (_playing) return;
    _playing = true;
    _escalated = false;
    await _configure();
    await _player.setVolume(1);
    await _player.play(AssetSource('sounds/new_order.wav'));
  }

  /// After a minute unacknowledged, get harder to ignore. A shop mid-rush is
  /// loud; the first pass can genuinely go unheard, and going quiet after one
  /// attempt is how an alarm becomes decorative.
  Future<void> escalate() async {
    if (!_playing || _escalated) return;
    _escalated = true;
    await _player.setPlaybackRate(1.15);
  }

  Future<void> stop() async {
    _playing = false;
    _escalated = false;
    await _player.stop();
  }

  /// Play once, at volume, for the settings screen. The failure mode of an alarm
  /// app is a muted device, and the only way to catch that is to make a noise on
  /// purpose before service rather than during it.
  Future<void> test() async {
    await _configure();
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.setVolume(1);
    await _player.play(AssetSource('sounds/new_order.wav'));
    await _player.setReleaseMode(ReleaseMode.loop);
  }

  bool get isPlaying => _playing;

  void dispose() => _player.dispose();
}
