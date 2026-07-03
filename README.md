# RooTheater

A multimedia player for **Sailfish OS 5.1**, focused on hardware-accelerated
playback of **local files and network streams**. Part of the `RooT*` app family.

Prerequisite: SFOS 5.1.0.11  
Telegram Group: https://t.me/+E7V-a7x4JbY1Njhk  
RooTheater is tested on:  
- Sony Xperia 10 III (SFOS 5.1.0.11)  
- Jolla C2 (SFOS 5.1.0.11)  

This application was developed using artificial intelligence technologies, specifically Warp Terminal and Claude Code Opus, but Warp Terminal has been gradually phased out in favor of Claude Code. Therefore, if the use of an application generated via a large-scale language model (LLM) is not comfortable for the user, it is recommended to avoid its installation and use. It is specified that any negative comment regarding this circumstance will not only be ignored but will result in the immediate blocking of the user.
I hereby disclaim any and all responsibility for the application, its functionality, and any consequences arising from its use. By choosing to use this application, the user acknowledges and accepts that they do so entirely at their own risk, and agrees that the developer shall not be held liable for any damages, losses, or adverse effects—whether direct, indirect, incidental, or consequential—resulting from the use or misuse of the application.

Requisiti: SFOS 5.1.0.11  
Gruppo Telegram: https://t.me/+E7V-a7x4JbY1Njhk  
RooTheater è testato:  
- Sony Xperia 10 III (SFOS 5.1.0.11)  
- Jolla C2 (SFOS 5.1.0.11)  

Questa applicazione è stata sviluppata utilizzando tecnologie di intelligenza artificiale, in particolare Warp Terminal e Claude Code Opus, ma Warp Terminal è stato abbandonato in favore di Claude Code. Pertanto, se l'uso di un'applicazione generata tramite un modello linguistico su larga scala (LLM) non fosse per l'utente confortevole, si raccomanda di evitarne l'installazione e l'uso. Si specifica che qualsiasi commento negativo riguardante questa circostanza non verrà solo ignorato, ma comporterà il blocco immediato dell'utente.
Con la presente declino ogni responsabilità relativa all’applicazione, al suo funzionamento e a qualsiasi conseguenza derivante dal suo utilizzo. L’utente, scegliendo di utilizzare l’applicazione, riconosce e accetta di farlo a proprio ed esclusivo rischio, e concorda che lo sviluppatore non potrà essere ritenuto responsabile per eventuali danni, perdite o effetti negativi — diretti, indiretti, incidentali o consequenziali — derivanti dall’uso o dall’uso improprio dell’applicazione.

## Media engine — layered design

On Sailfish OS the only real hardware video decode path is the Android HAL
exposed via `libhybris` → `droidmedia` → `gst-droid`. `libvlc` has no gst-droid
backend, so a "pure libvlc" app would fall back to software decode. RooTheater
therefore uses a **layered engine** behind a C++ facade, picking the best
backend per codec/source:

| Layer | Backend | Role | Status |
|------|---------|------|--------|
| 1 | **droidmedia** (direct) | Zero-copy HW decode: gralloc buffers → `EGLImage` → `QSGTexture` | planned (v0.3) |
| 2 | **QtMultimedia / GStreamer** | HW-accel for common formats via gst-droid | **baseline (v0.1)** |
| 3 | **libvlc** | Exotic protocols/codecs/subtitles; compiled per-arch | **done (v0.2)** |

The C++ facade (`MediaEngine`) lands in **v0.2**: it probes the source with
ffmpeg and routes it capability-driven to the backend that should play it
(`Droidmedia` / `QtMultimedia` / `Libvlc` / `Software`).

**Layer 1 is capability-driven, not hardcoded.** At startup it asks droidmedia
which OMX decoders the device actually exposes; the FFmpeg probe gives the
file's codec; if that codec is in the available HW set it takes the HW path,
otherwise it falls through to software. **H.264/AVC, H.265/HEVC and VP9 are the
guaranteed, optimised codecs.** Others (MPEG-2, MPEG-4 Part 2 ASP = DivX/Xvid,
VP8) get HW *opportunistically* when the device advertises them, else SW — no
per-codec hardcoding. (AVI is a container, demuxed by FFmpeg regardless; MPEG-2
/ MPEG-4 ASP content is SD/low-bitrate where SW decode is cheap and OMX support
is device-inconsistent, so they are not explicit HW targets.)

**ffmpeg** (`libavformat`/`libavcodec`/`libavutil`/`libswscale`/`libswresample`) is
the foundation of the engine facade, not a separate layer:

1. **Demux + parse** containers (MP4/MKV/TS/HLS…) to extract the elementary
   H.264/HEVC/VP9 bitstream that feeds the droidmedia HW decoder — the piece
   droidmedia itself lacks (it decodes but does not demux).
2. **Probe** codecs/tracks so the facade can pick the right backend.
3. **Software decode fallback** for codecs without HW support.

Note: libvlc already bundles ffmpeg internally and GStreamer has its own
demuxers, so ffmpeg-as-library mainly serves *our* Layer 1. It landed with the
facade in **v0.2**: we cross-build our own ffmpeg 7.0.2 as PIC static `.a` per
arch (`scripts/build-ffmpeg.sh`, LGPL — no x264/gpl) and **static-link** it, so
there is nothing to bundle, no RPATH and no spec excludes for ffmpeg.

## Status

**v0.1 (baseline)** — runnable Silica skeleton:
- Open a local file (Sailfish Pickers) or a network URL.
- Playback via `QtMultimedia` `MediaPlayer` + `VideoOutput` (HW-accelerated
  through gst-droid for common codecs).
- Player controls: play/pause, ±10s, seek slider, position/duration, tap to
  toggle overlay.

**v0.2 (facade + libvlc)** — the C++ media engine:
- `MediaEngine` facade: ffmpeg (`libavformat`/`libavcodec`) demux/probe off the
  GUI thread → capability-driven backend selection; the detected media and the
  chosen backend are surfaced in the player overlay.
- **Layer 3 libvlc 3.0.21** cross-built for SFOS (`scripts/build-libvlc.sh`),
  rendered into Qt Quick via the vmem CPU-buffer callbacks (`VlcBackend` +
  `VlcVideoOutput`); audio through libvlc's pulse output. libvlc/libvlccore +
  plugins are bundled per arch; ffmpeg is static-linked.
- `PlayerPage` routes to libvlc when the probe picks it, else the QtMultimedia
  baseline, behind one set of controls.
- Currently built/vendored for **aarch64**; armv7hl/i486 build at release.

## Roadmap

- **v0.3** — direct droidmedia HW decoder with zero-copy GL rendering for the
  popular codecs; fallback chain droidmedia → GStreamer → libvlc.
- Library/browse view, playback resume, subtitles, audio-track selection.

## Building from source (English)

RooTheater builds with the **Sailfish SDK** (`sfdk`). The app links/bundles
native dependencies that are *vendored per architecture*: FFmpeg (static `.a`)
and libVLC (`.so` + plugins). In this repo they may already be present under
`ffmpeg/<arch>/` and `vlc/<arch>/`; if not (e.g. a fresh clone of the public
mirror, or a new architecture), either **download the prebuilt vendor archive**
from the Releases page (fast) or **regenerate them from source** with the scripts
below — the scripts are the *corresponding source* of the LGPL/GPL components
(see [NOTICE.md](NOTICE.md)).

**Prerequisites**
- The [Sailfish SDK](https://docs.sailfishos.org/Tools/Sailfish_SDK/) installed,
  with `sfdk` on your `PATH`.
- The **SailfishOS-5.0.0.62** build target for your architecture — one of
  `aarch64`, `armv7hl`, `i486`.

**Steps** (replace `<arch>` with `aarch64`, `armv7hl` or `i486`):

1. **Clone**
   ```sh
   git clone https://github.com/RootGPT-YouTube/RooTheater-SailfishOS.git
   cd RooTheater-SailfishOS
   ```
2. **Install the build dependency** into the SDK target (once per arch):
   ```sh
   sfdk engine exec sb2 -t SailfishOS-5.0.0.62-<arch>.default \
        -m sdk-install -R zypper -n in droidmedia-devel
   ```
3. **Get the vendored dependencies** (FFmpeg + libVLC) — either option works:
   - **Download (fast):** grab `rootheater-vendor-<version>.tar.zst` from the
     [Releases](https://github.com/RootGPT-YouTube/RooTheater-SailfishOS/releases)
     page and extract it at the repo root:
     ```sh
     tar --zstd -xf rootheater-vendor-<version>.tar.zst   # → ffmpeg/<arch>/ + vlc/<arch>/
     ```
   - **Or rebuild from source** (the LGPL/GPL *corresponding source*):
     ```sh
     bash scripts/build-ffmpeg.sh <arch>      # → ffmpeg/<arch>/lib/*.a (static PIC, LGPL)
     bash scripts/build-libvlc.sh <arch>      # → vlc/<arch>/lib + .../vlc/plugins (long)
     ```
4. **Build the RPM**:
   ```sh
   sfdk -c target=SailfishOS-5.0.0.62-<arch> build
   # → RPMS/harbour-rootheater-<version>-1.<arch>.rpm
   ```
5. **Install on the device** (copy the RPM over, then on the phone):
   ```sh
   sudo pkcon install-local --allow-untrusted harbour-rootheater-<version>-1.<arch>.rpm
   ```

The `.pro` gates the libVLC layer on `vlc/<arch>/lib/libvlc.so` and droidmedia on
`packagesExist(droidmedia)`, so an arch without a vendored piece still builds
(without that layer) — check qmake's `message(...)` lines to confirm all layers
are active. On **i486** the scripts disable x86 asm (no nasm/yasm in the target).
For a full release, repeat steps 2–4 for each arch. Conventions shared with the
`RooT*` family: package `harbour-rootheater`, 3-arch RPMs, version single-sourced
from `RT_APP_VERSION` in the `.pro`.

## Compilare dai sorgenti (Italiano)

RooTheater si compila con il **Sailfish SDK** (`sfdk`). L'app linka/bundla
dipendenze native *vendorizzate per architettura*: FFmpeg (`.a` statiche) e
libVLC (`.so` + plugin). In questo repo possono già essere presenti in
`ffmpeg/<arch>/` e `vlc/<arch>/`; se mancano (es. clone pulito del mirror
pubblico, o una nuova architettura), puoi **scaricare l'archivio vendor
precompilato** dalla pagina Releases (veloce) oppure **rigenerarle da sorgente**
con gli script qui sotto — gli script sono la *corresponding source* dei
componenti LGPL/GPL (vedi [NOTICE.md](NOTICE.md)).

**Prerequisiti**
- Il [Sailfish SDK](https://docs.sailfishos.org/Tools/Sailfish_SDK/) installato,
  con `sfdk` nel `PATH`.
- Il target **SailfishOS-5.0.0.62** per la tua architettura — una tra
  `aarch64`, `armv7hl`, `i486`.

**Passi** (sostituisci `<arch>` con `aarch64`, `armv7hl` o `i486`):

1. **Clona**
   ```sh
   git clone https://github.com/RootGPT-YouTube/RooTheater-SailfishOS.git
   cd RooTheater-SailfishOS
   ```
2. **Installa la dipendenza di build** nel target dell'SDK (una volta per arch):
   ```sh
   sfdk engine exec sb2 -t SailfishOS-5.0.0.62-<arch>.default \
        -m sdk-install -R zypper -n in droidmedia-devel
   ```
3. **Procurati le dipendenze vendorizzate** (FFmpeg + libVLC) — vanno bene entrambe:
   - **Scarica (veloce):** prendi `rootheater-vendor-<versione>.tar.zst` dalla pagina
     [Releases](https://github.com/RootGPT-YouTube/RooTheater-SailfishOS/releases)
     ed estrailo nella radice del repo:
     ```sh
     tar --zstd -xf rootheater-vendor-<versione>.tar.zst   # → ffmpeg/<arch>/ + vlc/<arch>/
     ```
   - **Oppure ricompila da sorgente** (la *corresponding source* LGPL/GPL):
     ```sh
     bash scripts/build-ffmpeg.sh <arch>      # → ffmpeg/<arch>/lib/*.a (statiche PIC, LGPL)
     bash scripts/build-libvlc.sh <arch>      # → vlc/<arch>/lib + .../vlc/plugins (lunga)
     ```
4. **Compila l'RPM**:
   ```sh
   sfdk -c target=SailfishOS-5.0.0.62-<arch> build
   # → RPMS/harbour-rootheater-<versione>-1.<arch>.rpm
   ```
5. **Installa sul dispositivo** (copia l'RPM, poi sul telefono):
   ```sh
   sudo pkcon install-local --allow-untrusted harbour-rootheater-<versione>-1.<arch>.rpm
   ```

Il `.pro` abilita il layer libVLC solo se esiste `vlc/<arch>/lib/libvlc.so` e
droidmedia solo se `packagesExist(droidmedia)`, quindi un'arch senza un pezzo
vendorizzato si compila comunque (senza quel layer) — controlla i `message(...)`
di qmake per confermare che ogni layer sia attivo. Su **i486** gli script
disabilitano l'assembly x86 (nel target non c'è nasm/yasm). Per un rilascio
completo, ripeti i passi 2–4 per ogni arch.

## YouTube & trademarks

RooTheater's YouTube feature is a thin convenience layer over public,
unauthenticated interfaces:

- **Subscriptions** are read from each channel's public **RSS feed** — no Google
  API key, no OAuth, no login.
- **Playback** opens YouTube's own **official web player** (`m.youtube.com`) inside
  the Sailfish WebView (the same Gecko engine as the system browser),
  unmodified. RooTheater does **not** download, extract,
  re-host, transcode or otherwise redistribute any YouTube content or streams.

Using the Sailfish WebView / WebEngine QML modules is ordinary use of the
operating system's public APIs; those components are provided by SailfishOS at
runtime and are **not** bundled or redistributed by RooTheater (the bundled
third-party libraries — FFmpeg, libVLC and its contrib — are listed separately
in [NOTICE.md](NOTICE.md)).

*"YouTube" is a trademark of Google LLC. RooTheater is an independent project,
**not affiliated with, sponsored by or endorsed by** Google LLC or YouTube; the
name is used solely for identification.*

## YouTube e marchi (Italiano)

La funzione YouTube di RooTheater è un sottile livello di comodità sopra
interfacce pubbliche e non autenticate:

- Le **iscrizioni** vengono lette dal **feed RSS pubblico** di ciascun canale —
  nessuna API key di Google, nessun OAuth, nessun login.
- La **riproduzione** apre il **player web ufficiale** di YouTube
  (`m.youtube.com`) dentro la Sailfish WebView (lo stesso motore Gecko del browser
  di sistema), non modificato. RooTheater **non**
  scarica, estrae, ri-ospita, transcodifica né ridistribuisce in alcun modo i
  contenuti o gli stream di YouTube.

L'uso dei moduli QML Sailfish WebView / WebEngine è normale utilizzo delle API
pubbliche del sistema operativo; tali componenti sono forniti da SailfishOS a
runtime e **non** vengono impacchettati o ridistribuiti da RooTheater (le librerie
di terze parti effettivamente incluse — FFmpeg, libVLC e i suoi contrib — sono
elencate a parte in [NOTICE.md](NOTICE.md)).

*"YouTube" è un marchio di Google LLC. RooTheater è un progetto indipendente,
**non affiliato, sponsorizzato o approvato** da Google LLC o YouTube; il nome è
usato solo a scopo identificativo.*

## License

GPL-3.0 © 2026 RootGPT.
