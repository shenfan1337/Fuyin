# Third-party notices

## Lyricify Lyrics Helper

Project: https://github.com/WXRIW/Lyricify-Lyrics-Helper

License: Apache License, Version 2.0. Full text: Lyricify-Lyrics-Helper/LICENSE.

QQMusicLyrics.ps1 adapts the Search, GetSong and GetLyric request construction and base64 lyric decoding from Lyricify.Lyrics.Helper/Providers/Web/QQMusic/Api.cs. The original upstream file, downloaded from the master branch on 2026-10-19, is retained as Lyricify-Lyrics-Helper/Original-QQMusic-Api.cs. Changes: PowerShell 5.1 port, Fuyin's recording validation, response disposal, input validation and safe JSONP-envelope parsing. No original Lyricify application UI or proprietary binaries are included.

## KRC word timing

KrcReader.cs and KugouLyrics.ps1 adapt the public KRC text container protocol and KuGou search/download request construction documented by Lyricify Lyrics Helper (Apache-2.0, project linked above). Original upstream Decrypter/Krc/Decrypter.cs, Decrypter/Krc/Helper.cs and Providers/Web/Kugou/Api.cs are retained as Original-Krc-Decrypter.cs, Original-Krc-Helper.cs and Original-Kugou-Api.cs in Lyricify-Lyrics-Helper/. Downloaded from the master branch on 2026-10-20. Changes: built-in .NET DeflateStream instead of SharpZipLib, strict UTF-8 and bounded text decoding, PowerShell 5.1 requests with response disposal, recording checks, word-boundary line splitting and alignment to the existing player lyric lines. No audio, account cookies or executable content is downloaded by this provider. Lyrics themselves remain the property of their respective rights holders and are fetched at runtime; song fixtures are not distributed.

## Optional NetEase integration

The installer downloads unmodified upstream releases directly to the user's machine, verifies fixed SHA-256 digests, and does not overwrite other versions. The following binaries are not redistributed inside Fuyin's archive:

- BetterNCM 1.3.4: https://github.com/std-microblock/chromatic/releases/tag/1.3.4 ; archived project source: https://github.com/std-microblock/chromatic/tree/v2
- InfLink-rs 3.4.0 (GPL-3.0): https://github.com/apoint123/inflink-rs/releases/tag/v3.4.0 ; corresponding source: https://github.com/apoint123/inflink-rs/tree/v3.4.0

The NCM-{id} and QQ-{id} metadata interoperability is based on the public documentation of InfLink-rs and QQMusic-ID-Injector. Fuyin does not include or install QQMusic-ID-Injector.

Compatibility guidance follows Lyricify Lite's published application support guide: https://github.com/WXRIW/Lyricify-App/blob/main/docs/Lyricify%20Lite/README.md
