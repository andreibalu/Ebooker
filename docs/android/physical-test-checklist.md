# Physical test checklist

The emulator suite (39 E2E journeys, 231 host tests) covers everything an
emulator can run. This list covers what only a real phone, car or Google account
can prove. Record each result next to its item, with the phone model and Android
version.

## Install

1. On the phone, enable Developer options and USB debugging.
2. Connect it and run from `android/`:

   ```bash
   "$ANDROID_HOME/platform-tools/adb" install -r app/build/outputs/apk/debug/app-debug.apk
   ```

   Without a cable, copy `app-debug.apk` to the phone and open it. Android asks
   to allow installs from that app once.

The debug build installs as "Unpaged" with the id
`dev.unpaged.android.development`, next to any future Play build.

## Playback

- [ ] Import an M4B with chapters and an MP3 folder. Chapter list and next and
      previous chapter match the iPhone app.
- [ ] Lock the phone during playback. Audio continues for 30 minutes and the
      lock screen controls pause, resume and skip.
- [ ] Bluetooth headphones: play and pause buttons work. Disconnecting pauses.
- [ ] A phone call pauses playback. It resumes after the call ends.
- [ ] Stream a LibriVox book on mobile data, then switch Wi-Fi on and off.
- [ ] Download a LibriVox book, enable airplane mode, and play it.
- [ ] EQ presets audibly change the sound on speaker and headphones.
- [ ] Sleep timer stops playback at the set time.

## Android Auto

- [ ] Connect to a car or the Desktop Head Unit. The library, recent books and
      chapters appear.
- [ ] Play, pause, skip and chapter jumps work from the car screen.
- [ ] Voice: "Play <book title> on Unpaged" starts the book.
- [ ] Save a moment from the car. It appears on the phone.

## On-device AI

Gemini Nano needs a supported phone, such as a Pixel 9 or later or a recent
Samsung Galaxy S. On other phones the AI settings say the feature is unavailable
and the rest of the app works.

- [ ] Settings, On-device AI shows "Ready" for Gemini Nano on a supported phone.
- [ ] Download the speech model (59.7 MB). Delete it, and the storage is freed.
- [ ] Smart save names a moment from the audio in a few seconds.
- [ ] Smart summary writes a recap on the book detail screen.
- [ ] In airplane mode, both features still work after the model is downloaded.
- [ ] On an unsupported phone, AI rows are hidden or marked unavailable, with no
      crash.

## Backup and restore

- [ ] With Backup by Google on, run `adb shell bmgr backupnow dev.unpaged.android.development`,
      uninstall, reinstall and restore. Books, progress and moments come back,
      marked as missing audio.
- [ ] Re-import the same audio files. The restore match sheet appears and keeps
      progress and moments.
- [ ] Phone-to-phone transfer during new phone setup carries the library over.
- [ ] Turning the in-app backup toggle off keeps the library out of the next
      backup.

## Audiobookshelf

- [ ] Connect to your server on LAN and over Tailscale. Browse, stream and check
      that progress appears on the server.

## Look and feel

- [ ] Compare the library, player, book detail, Settings and onboarding against
      the iPhone in light and dark mode.
- [ ] Large system font and display size settings keep text readable.

## Before a Play Store release

These are not needed for your own testing:

- A release signing key and a Play Console app entry.
- A final application id. The debug build uses `dev.unpaged.android.development`.
- Android sections in `privacy-policy.md`, `support.md` and `EULA.md`, covering
  Gemini Nano, the speech model download from Hugging Face and Android backup.
  Then update the Gist mirrors.
