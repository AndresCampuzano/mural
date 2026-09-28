# Mural screenshots — Korean

Three original PNG captures from the iPhone 17 simulator, iOS 26.2, taken on 17 September 2026 with a 09:41 status bar, full signal and full battery. No device frame, resizing or image retouching.

1. **01-greeting.png** — Korean greeting and voice controls.
2. **02-conversation.png** — Sample café conversation with English meaning subtitles.
3. **03-themes.png** — The Korean module's theme selection.

The interface and meanings remain in English, as in the app. Dialogue is sample data supplied through a simulator-only debug preview, not real conversations or measured learning progress. The preview makes no API requests.

To reproduce, build the Debug simulator target, then launch with `--preview --screenshot=greeting`, `conversation` or `themes` as the screenshot value. Capture through `xcrun simctl io <simulator-id> screenshot <absolute-output-path>`.
