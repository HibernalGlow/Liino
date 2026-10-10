<p align="center">
  <img src="assets/branding/readme_logo.png" width="140" height="100" />
</p>

<p align="center">
  <b>A local music player for Android and Linux that takes its colours from whatever you're playing.</b>
</p>

<p align="center">
  <img src="https://img.shields.io/github/v/release/SthrNilshaaa/looper?style=flat-square&color=000000" />
  <img src="https://img.shields.io/github/downloads/SthrNilshaaa/looper/total?style=flat-square&color=000000" />
  <img src="https://img.shields.io/github/stars/SthrNilshaaa/looper?style=flat-square&color=000000" />
  <img src="https://img.shields.io/badge/platform-Android%20%7C%20Linux-blueviolet?style=flat-square" />
  <img src="https://img.shields.io/badge/license-GPL--3.0-green?style=flat-square" />
</p>

<p align="center">
  <a href="https://play.google.com/store/apps/details?id=com.looper.player">
    <img src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" alt="Get it on Google Play" height="70">
  </a>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#screenshots">Screenshots</a> •
  <a href="#installation">Install</a> •
  <a href="#tech-stack">Built with</a> •
  <a href="#contributors">Credits</a> •
  <a href="#contact">Contact</a>
</p>

<p align="center">
  <img src="media/screenshots/now_playing.png" width="16%" alt="Now playing" />
  <img src="media/screenshots/lyrics.png" width="16%" alt="Lyrics" />
  <img src="media/screenshots/home.png" width="16%" alt="Home" />
  <img src="media/screenshots/library.png" width="16%" alt="Library" />
  <img src="media/screenshots/analyze.png" width="16%" alt="Looper Analyze" />
  <img src="media/screenshots/settings.png" width="16%" alt="Settings" />
</p>

---

## What is Looper?

Looper plays the music files you already own. Point it at a folder and it builds a library you can browse by song, album, artist, genre or folder, then gets out of the way.

We started it because we wanted one player that looks the same on a phone and on a Linux desktop, and that makes the album art the centre of the screen. The player, the lyrics page and the accents across the app all pick up the colours of the current cover.

There is no account, no ads and no subscription. Your music stays on your device; the app goes online only for things like fetching lyrics and checking for updates.

<a id="features"></a>
## Features

<img src="media/output.gif" align="right" width="170" alt="Word-synced lyrics" />

- **Lyrics that follow the song.** Word-by-word or line-by-line highlighting, tap a line to jump to it, adjust the offset if the timing is off. Lyrics are fetched online or loaded from your own `.lrc` file.
- **Looper Analyze.** A report card for your listening: time listened, streaks, top songs and artists, busiest day, and a genre breakdown.
- **Colours from the artwork.** The player background, buttons and highlights change with each track. Or pick your own theme and font.
- **18-band equalizer.** Drag the curve to shape the sound, ±20 dB per band.
- **Picks up where you left off.** The queue, the track and the position are restored when you reopen the app.
- **Fast search.** Search by title, artist, album, or a line of the lyrics.
- **Home-screen widgets** on Android, in 12 layouts.
- **A real desktop layout** on Linux, with a sidebar, wide grids, media keys and MPRIS.
- **14 languages**, including Hindi, Arabic, Japanese, Korean and Chinese.
- **Backups.** Export your app data and import it again later.

<br clear="right"/>

---

<a id="screenshots"></a>
## Screenshots

### Android

<p align="center">
  <img src="media/screenshots/now_playing.png" width="32%" alt="Now playing" />
  <img src="media/screenshots/lyrics.png" width="32%" alt="Lyrics" />
  <img src="media/screenshots/analyze.png" width="32%" alt="Looper Analyze" />
</p>
<p align="center">
  <img src="media/screenshots/home.png" width="32%" alt="Home" />
  <img src="media/screenshots/library.png" width="32%" alt="Library" />
  <img src="media/screenshots/settings.png" width="32%" alt="Settings" />
</p>

### Linux

<p align="center">
  <img src="media/gallery/analyze.png" width="49%" alt="Looper Analyze on desktop" />
  <img src="media/gallery/lyrics.png" width="49%" alt="Lyrics on desktop" />
</p>
<p align="center">
  <img src="media/gallery/home.png" width="32%" alt="Home" />
  <img src="media/gallery/albums.png" width="32%" alt="Albums" />
  <img src="media/gallery/artists.png" width="32%" alt="Artists" />
</p>
<p align="center">
  <img src="media/gallery/songs.png" width="24%" alt="Songs" />
  <img src="media/gallery/album_detail.png" width="24%" alt="Album" />
  <img src="media/gallery/album_playing.png" width="24%" alt="Album while playing" />
  <img src="media/gallery/lyrics_synced.png" width="24%" alt="Synced lyrics" />
</p>

---

<a id="installation"></a>
## Installation

Android is on [Google Play](https://play.google.com/store/apps/details?id=com.looper.player). Everything else is on the [Releases](https://github.com/SthrNilshaaa/looper/releases) page.

### Android (`.apk`)
- Download the APK for your phone. `arm64-v8a` is right for almost every phone from the last several years; use `armeabi-v7a` for older ones and `x86_64` for emulators.
- Open it and tap **Install**. Android will ask you to allow installs from your browser or file manager the first time.
- The GitHub build can update itself from inside the app.

### Linux

#### Debian / Ubuntu / Mint (`.deb`)
```bash
sudo apt install ./looper-player.deb
```

#### Fedora / RHEL / CentOS (`.rpm`)
```bash
# Fedora
sudo dnf install ./looper-player.rpm
# openSUSE
sudo zypper install ./looper-player.rpm
```

#### AppImage
Nothing to install. Make it executable and run it:
```bash
chmod +x looper-player.AppImage
./looper-player.AppImage
```

#### Portable Archive (`.tar.gz`)
Extract and run from anywhere:
```bash
tar -xzvf looper-player-linux.tar.gz
cd universal
./run.sh
```

---

<a id="tech-stack"></a>
## Built with

| | |
| :--- | :--- |
| UI | Flutter & Dart |
| State | Riverpod |
| Database | Isar (local, on-device) |
| Playback | mpv, through `mpv_audio_kit` |
| Tags | `metadata_god` |

---

<a id="contributors"></a>
## Credits

### Team
* **Nilesh Suthar** — development
* **Karan Suthar** — design

### Lyrics Sources
Online lyrics come from these services and projects. Lyrics belong to their artists and rights holders and are fetched for personal display only.
* **[lrc.red](https://lrc.red)**: word-synced lyrics (the default provider)
* **[LyricsPlus](https://github.com/ibratabian17/lyricsplus)**: word-synced lyrics. It's an open-source server by ibratabian17 (Apache-2.0), hosted by binimum.
* **[AMLL](https://amll.dev)**, **[NetEase](https://music.163.com)**, **[KuGou](https://www.kugou.com)**, **[Musixmatch](https://www.musixmatch.com)** and **[Lyricify](https://lyricify.app)**: word-synced lyrics, asked after the two above. You can reorder the services or switch any of them off in Settings.
* **[LRCLIB](https://lrclib.net)**: line-synced lyrics from a free, open database
* **[MusicBrainz](https://musicbrainz.org)**: finds each song's ISRC so lrc.red can match it (open music database, CC0 data)
* **[am-lyrics](https://github.com/binimum/am-lyrics)** by binimum (MPL-2.0): inspired Looper's word-synced lyrics support. No code was copied; Looper's Dart implementation was written from the lyrics formats.
* **[Morphe Patches](https://github.com/MorpheApp/morphe-patches)** (GPL-3.0): reference for the NetEase, KuGou, Musixmatch and Lyricify lookups and their lyrics formats.

---

## License

This project is licensed under the GPL-3.0 License.

---

<a id="contact"></a>
## Contact

Found a bug or want a feature? Open an [issue](https://github.com/SthrNilshaaa/looper/issues) or say hi on Telegram:

[![Telegram](https://img.shields.io/badge/Telegram-26A5E4?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/looperPlayer)
