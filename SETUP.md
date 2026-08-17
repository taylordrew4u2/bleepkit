# BleepKit — Setup

BleepKit is an iOS app that transcribes short-form vertical video entirely
on-device, burns in animated captions, detects profanity, and censors it in
three synchronized layers (beep, caption treatment, video overlay). No
third-party code, no network calls — it works identically in Airplane Mode.

## Requirements

- Xcode 26 or later (latest stable).
- A physical iPhone running iOS 18.0 or later. iOS 26+ uses the
  `SpeechAnalyzer` transcription engine; iOS 18–25 falls back to
  `SFSpeechRecognizer`.
- An Apple ID. A paid Apple Developer Program membership is **not** required
  — a free personal team works.

## Signing with a personal certificate

1. Open `bleepkit.xcodeproj` in Xcode.
2. Select the blue project icon → TARGETS → **bleepkit** → **Signing &
   Capabilities**.
3. Check **Automatically manage signing**.
4. Under **Team**, choose your personal team (add your Apple ID in
   Xcode → Settings → Accounts if the list is empty).
5. If the bundle identifier collides with someone else's, change it to
   something unique (e.g. `yourname.bleepkit`).

## Running on your iPhone

1. Connect the iPhone by cable (or enable network debugging later).
2. Pick your device in the run-destination bar and press **⌘R**.
3. First run only, on the phone: **Settings → General → VPN & Device
   Management** → trust your developer certificate. If prompted, also enable
   **Developer Mode** (Settings → Privacy & Security → Developer Mode) and
   restart the phone.

### The 7-day provisioning expiry (free accounts)

Apps signed with a free personal team expire after **7 days**. When the app
stops launching, reconnect the phone and press ⌘R again — re-installing
renews the profile. Projects and their imported videos survive
re-installation only if the app is not deleted; deleting the app deletes its
documents.

Free accounts are also limited to ~3 installed development apps at a time.

## Deployment target configuration

The project is configured for:

- iOS **18.0** deployment target, iPhone only, portrait only
- **Swift 6** language mode with strict concurrency
- Supported platforms: iPhone device and simulator only

These live in the target's Build Settings; nothing needs changing for a
normal build.

## First run and the iOS 26 language model

On iOS 26+, the first transcription needs the on-device speech model, which
iOS downloads on demand (the UI shows "Preparing language model…"). This is
a one-time system download shared between apps; it requires network **once**.
If the download is unavailable (for example, first run in Airplane Mode),
BleepKit automatically falls back to the legacy `SFSpeechRecognizer` engine,
using its on-device recognition when the locale supports it. After the model
is installed, everything — transcription included — runs fully offline.

## Permissions the app requests (at point of use, never at launch)

| Permission | When | Why |
| --- | --- | --- |
| Speech Recognition | First transcription | On-device captioning; audio never leaves the phone |
| Photo Library (add-only) | First export | Saving the finished video into the "BleepKit" album |

Videos are picked through the system photo picker, which needs no
permission.

## Unit tests

Test sources live in `bleepkitTests/`. The test bundle target must exist in
the project (File → New → Target… → **Unit Testing Bundle**, named
`bleepkitTests`, host application `bleepkit`); then run with **⌘U**.
