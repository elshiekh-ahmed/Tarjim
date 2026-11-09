# Tarjim ترجم

An iOS keyboard that translates between **English** and **Sudanese Arabic** right inside Messages (or any app). Translations use Google's **Gemini API free tier**.

- **Read their message:** long-press it in Messages › **Copy** › tap **Read copied** on the keyboard. The English translation appears above the keys, with notes on any slang.
- **Reply:** type in English. A live Sudanese Arabic preview shows above the keys, with an English back-translation so you can check the meaning. Tap **Insert Arabic** to replace your English in the message box. Review it, then send. Tap **English** to undo.

> iOS doesn't let third-party apps add buttons to message bubbles or read your conversations, so copying their message is the one manual step.

## Install (no Mac needed)

1. Download `Tarjim.ipa` from the [latest release](../../releases/latest).
2. Sideload it with [Sideloadly](https://sideloadly.io) (Windows/Mac) or [AltStore](https://altstore.io), signing in with your Apple ID.
   - A free Apple ID works, but the app expires after 7 days. Re-sign it to keep using it (AltStore can do this automatically). Free Apple IDs can have 3 sideloaded apps active at once, and Tarjim plus its keyboard count as 2.
   - Enable **Developer Mode** on the iPhone if asked: Settings › Privacy & Security › Developer Mode.
3. Trust the profile: Settings › General › VPN & Device Management.

## Set up

1. Get a free API key at <https://aistudio.google.com/apikey>.
2. Open **Tarjim**, paste the key, and tap **Test key**.
3. Settings › General › Keyboard › Keyboards › **Add New Keyboard…** › **Tarjim**. Then tap **Tarjim** and turn on **Allow Full Access**. Full Access is required for internet access and for reading copied text.
4. In Messages, hold 🌐 and choose **Tarjim**.

If the keyboard says there's no API key even though you added it in the app, your sideloading tool didn't keep the App Group. Copy your key, then tap **Paste key from clipboard** on the keyboard.

## Options

- **Reply script:** Arabic script (default) or Arabizi (Latin letters such as `3`, `7`).
- **Model:** defaults to `gemini-flash-latest`. If that model isn't available, Tarjim tries `gemini-3.5-flash-lite` and then `gemini-2.5-flash`.

## Privacy

The text you translate is sent to Google's Gemini API. On the free tier, Google may use this data to improve its products. Your API key is stored only on your device.

## Build

GitHub Actions (`.github/workflows/build.yml`) generates the Xcode project with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and builds an unsigned IPA on macOS. Pushing a `v*` tag publishes a release.
