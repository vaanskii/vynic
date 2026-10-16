> **Superseded:** the film no longer has narration. The story is told by on-screen Georgian captions; see `CAPTIONS_GE.md`. This file is kept for reference only.

# Vynic launch film: Georgian voice-over (ქართული ნარაცია)

**Status:** the voice track is a TEMPORARY AI voice. Replace it before release (see "Replacing the voice").

## Voice direction

- **Voice:** male, calm, premium, natural, confident, slightly deep, modern and restrained.
- **Not:** a radio announcer, a trailer voice, dramatic, robotic, or rushed.
- **Pace:** unhurried, with short pauses at the dashes and full stops. Pauses inside a line are capped at about 0.45s.
- **Pronunciation:**
  - **Vynic:** "ვაინიკ" (VAI-nik). The repository always writes the name in Latin script and never spells it out, so **please confirm the intended pronunciation.**
  - **SaaS:** "საას".
  - **Custom:** "ქასთომ".
  - **POS:** "პოს".

## Script (11 lines, about 88 words, about 44 s of speech in 60 s)

| # | Georgian (as written) | English meaning (for review) |
|---|---|---|
| 01 | რესტორნის მართვა მხოლოდ შეკვეთების მიღება არ არის. | Running a restaurant is not just taking orders. |
| 02 | მაგიდები, შეკვეთები, მომსახურება და დღის ოპერაცია — ყველაფერი იწყება Vynic POS-ში. | Tables, orders, service and the day's operation: it all starts in Vynic POS. |
| 03 | სწრაფად. ადგილობრივად. რესტორნის რეალურ სამუშაო პროცესზე მორგებულად. | Fast. Local. Built around how a restaurant really works. |
| 04 | რესტორნის ინფორმაცია ერთ სისტემაში ერთიანდება — იქ, სადაც მართვა, მონაცემები და ონლაინ გამოცდილება ერთმანეთს უკავშირდება. | The restaurant's information comes together in one system, where management, data and the online experience connect. |
| 05 | მენეჯერი ხედავს არა მხოლოდ გაყიდვებს. | The manager sees more than sales. |
| 06 | მიღებები, მარაგები, მომწოდებლები და ვალდებულებები — რესტორნის მდგომარეობა ერთ ადგილას იკითხება. | Receiving, stock, suppliers and obligations: the restaurant's state, readable in one place. |
| 07 | ონლაინ კი იგივე რესტორანი შეიძლება გამოჩნდეს ისე, როგორც მის ბრენდს შეეფერება. | Online, the same restaurant can appear the way its brand deserves. |
| 08 | Vynic SaaS — სწრაფი და მზად გამოსაყენებლად. | Vynic SaaS: fast and ready to use. |
| 09 | ან სრულიად ინდივიდუალური Custom გამოცდილება. | Or a fully individual Custom experience. |
| 11 | ერთი რესტორანი. ერთი დაკავშირებული სისტემა. | One restaurant. One connected system. |
| 12 | Vynic. | Vynic. |

- **Line 10 was cut:** "POS, მენეჯერი და ვებსაიტი — ერთ საფუძველზე" made the speech too dense and repeated line 11. The id is kept free so the numbering doesn't shift.
- **Word count:** about 88 spoken words, slightly under the 95–125 target. Georgian words are long, and 44 s of speech is already 73% of the film. More lines would remove the music-only breaths the brief asks for.

## Claims check

- **No absolute guarantees:** no "100%", "zero data loss", "offline" or "realtime" claim.
- **"ადგილობრივად" (locally):** describes the POS as a local application, which is true, and makes no guarantee.
- **No ranking claims:** no "best" or "#1".
- **Line 09:** says "individual" and never "automatic".

## Temporary voice: source and licence

- **Engine:** Microsoft Edge neural text-to-speech, voice **ka-GE-GiorgiNeural** (male, Georgian), through the open-source `edge-tts` CLI. Settings: rate −3%, pitch −6 Hz.
- **Licence:** this service is **not licensed for commercial production**. It is suitable only as a placeholder for timing and review.
- **Why this voice:** no HeyGen sign-in, no Gemini or ElevenLabs key, and 0 Higgsfield credits were available. The local Kokoro model has no Georgian.

## Replacing the voice (no composition rebuild)

Each line is its own file: `assets/audio/vo/vo-01.wav` … `vo-12.wav`. The composition places each file by `data-start`, and all of them belong to the `voiceover` audio group. The music bed is carved against that group, so it ducks under whatever voice is there.

1. Record or generate the same lines and export each as `vo-XX.wav` (48 kHz WAV, trimmed, peaks around −3 dBFS).
2. Drop them over the temporary files.
3. If a new line is longer or shorter, adjust its `data-start` / `data-duration` in `index.html` (the `<audio class="vo">` block) and in `VOICEOVER_TIMING.md`.
4. Re-run the music carve (see README), then `npm run render` (master + stems + all versions).

To regenerate the temporary voice: `EDGE_TTS=/path/to/edge-tts npm run tts` (lines are listed in `audio/vo-lines.json`).
