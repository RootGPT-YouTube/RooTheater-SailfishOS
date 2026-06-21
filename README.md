# RooTheater

A multimedia player for SailfishOS — hardware-accelerated playback of local
files and network streams.

- **App name:** RooTheater
- **Author:** RootGPT
- **Version:** 0.5.0
- **Platform:** SailfishOS 5.0+
- **License:** GPLv3 (see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md))

## English

Prerequisite: SFOS 5.0/5.1  
Telegram Group: https://t.me/+E7V-a7x4JbY1Njhk  
RooTheater is tested on:  
- Sony Xperia 10 III (SFOS 5.0)  
- Jolla C2 (SFOS 5.1.0.10)  

## This application was developed using artificial intelligence technologies, specifically Warp Terminal and Claude Code Opus, but Warp Terminal has been gradually phased out in favor of Claude Code. Therefore, if the use of an application generated via a large-scale language model (LLM) is not comfortable for the user, it is recommended to avoid its installation and use. It is specified that any negative comment regarding this circumstance will not only be ignored but will result in the immediate blocking of the user.
## I hereby disclaim any and all responsibility for the application, its functionality, and any consequences arising from its use. By choosing to use this application, the user acknowledges and accepts that they do so entirely at their own risk, and agrees that the developer shall not be held liable for any damages, losses, or adverse effects—whether direct, indirect, incidental, or consequential—resulting from the use or misuse of the application.

RooTheater is a multimedia player for SailfishOS that plays both local media
files and network streams. It is built around a **layered media engine**: on
Sailfish the only real hardware video decode path is the Android HAL exposed
via `libhybris` → `droidmedia` / `gst-droid`, so RooTheater combines a custom
hardware path for the popular codecs (H.264/HEVC/VP9, zero-copy into the Qt
scene graph) with QtMultimedia/GStreamer and libVLC as fallbacks for broad
format and streaming coverage. FFmpeg provides container demuxing, codec
probing and software decoding.

This release (v0.1) is the baseline: a Silica UI to open a local file or a
network URL, played through QtMultimedia (hardware-accelerated via gst-droid)
with basic playback controls.

## Italiano

Requisiti: SFOS 5.0/5.1  
Gruppo Telegram: https://t.me/+E7V-a7x4JbY1Njhk  
RooTheater è testato:  
- Sony Xperia 10 III (SFOS 5.0)  
- Jolla C2 (SFOS 5.1.0.8)  

## Questa applicazione è stata sviluppata utilizzando tecnologie di intelligenza artificiale, in particolare Warp Terminal e Claude Code Opus, ma Warp Terminal è stato abbandonato in favore di Claude Code. Pertanto, se l'uso di un'applicazione generata tramite un modello linguistico su larga scala (LLM) non fosse per l'utente confortevole, si raccomanda di evitarne l'installazione e l'uso. Si specifica che qualsiasi commento negativo riguardante questa circostanza non verrà solo ignorato, ma comporterà il blocco immediato dell'utente.
## Con la presente declino ogni responsabilità relativa all’applicazione, al suo funzionamento e a qualsiasi conseguenza derivante dal suo utilizzo. L’utente, scegliendo di utilizzare l’applicazione, riconosce e accetta di farlo a proprio ed esclusivo rischio, e concorda che lo sviluppatore non potrà essere ritenuto responsabile per eventuali danni, perdite o effetti negativi — diretti, indiretti, incidentali o consequenziali — derivanti dall’uso o dall’uso improprio dell’applicazione.

RooTheater è un lettore multimediale per SailfishOS che riproduce sia file
locali sia stream di rete. È costruito attorno a un **motore a livelli**: su
Sailfish l'unica vera via di decodifica video hardware è l'Android HAL esposto
tramite `libhybris` → `droidmedia` / `gst-droid`, perciò RooTheater unisce un
percorso hardware dedicato ai codec più diffusi (H.264/HEVC/VP9, zero-copy
nella scene graph di Qt) con QtMultimedia/GStreamer e libVLC come fallback per
un'ampia compatibilità di formati e streaming. FFmpeg si occupa di demux dei
container, analisi dei codec e decodifica software.

Questa versione (v0.1) è la base: un'interfaccia Silica per aprire un file
locale o un URL di rete, riprodotti tramite QtMultimedia (accelerazione
hardware via gst-droid) con i controlli di riproduzione essenziali.

## Building from source (English)

RooTheater builds with the **Sailfish SDK** (`sfdk`). This public repository
ships the application sources and the *vendoring scripts*, but **not** the
prebuilt native dependencies (FFmpeg static libraries, libVLC `.so` + plugins):
you regenerate those per architecture with the scripts below. This keeps the
repo light while still providing the *corresponding source* required by the
LGPL/GPL components (see [NOTICE.md](NOTICE.md)).

**Prerequisites**
- The [Sailfish SDK](https://docs.sailfishos.org/Tools/Sailfish_SDK/) installed,
  with `sfdk` on your `PATH`.
- The **SailfishOS-5.0.0.62** build target for your architecture — one of
  `aarch64`, `armv7hl`, `i486`.

**Steps** (replace `<arch>` with `aarch64`, `armv7hl` or `i486`):

1. **Clone the repository**
   ```sh
   git clone https://github.com/RootGPT-YouTube/RooTheater-SailfishOS.git
   cd RooTheater-SailfishOS
   ```
2. **Install the build dependency** into the SDK target (once per arch). The
   direct HW path links `droidmedia`:
   ```sh
   sfdk engine exec sb2 -t SailfishOS-5.0.0.62-<arch>.default \
        -m sdk-install -R zypper -n in droidmedia-devel
   ```
3. **Vendor FFmpeg** — static PIC `.a`, built LGPL (no `--enable-gpl`, no x264):
   ```sh
   bash scripts/build-ffmpeg.sh <arch>      # → ffmpeg/<arch>/lib/*.a
   ```
4. **Vendor libVLC** — bundled `.so` + plugins; long, builds VLC's contrib
   (incl. its own FFmpeg) from source:
   ```sh
   bash scripts/build-libvlc.sh <arch>      # → vlc/<arch>/lib + vlc/<arch>/lib/vlc/plugins
   ```
5. **Build the RPM**:
   ```sh
   sfdk -c target=SailfishOS-5.0.0.62-<arch> build
   # → RPMS/harbour-rootheater-<version>-1.<arch>.rpm
   ```
6. **Install on the device** (copy the RPM over, then on the phone):
   ```sh
   sudo pkcon install-local --allow-untrusted harbour-rootheater-<version>-1.<arch>.rpm
   ```

**Notes**
- The `.pro` gates the libVLC layer on `vlc/<arch>/lib/libvlc.so` existing and
  the droidmedia layer on `packagesExist(droidmedia)`: if a vendored piece is
  missing the app still builds, just **without that layer**. Check qmake's
  `message(...)` output ("libvlc backend enabled…", "droidmedia HW path enabled")
  to confirm every layer is active.
- On **i486** the scripts disable x86 assembly automatically (the SFOS i486
  target ships no nasm/yasm).
- For a full 3-architecture release, repeat steps 2–5 for each `<arch>`.

## Compilare dai sorgenti (Italiano)

RooTheater si compila con il **Sailfish SDK** (`sfdk`). Questo repository
pubblico contiene i sorgenti dell'app e gli *script di vendoring*, ma **non** le
dipendenze native precompilate (librerie statiche di FFmpeg, `.so` + plugin di
libVLC): le rigeneri per architettura con gli script qui sotto. Così il repo
resta leggero pur fornendo la *corresponding source* richiesta dai componenti
LGPL/GPL (vedi [NOTICE.md](NOTICE.md)).

**Prerequisiti**
- Il [Sailfish SDK](https://docs.sailfishos.org/Tools/Sailfish_SDK/) installato,
  con `sfdk` nel `PATH`.
- Il target di build **SailfishOS-5.0.0.62** per la tua architettura — una tra
  `aarch64`, `armv7hl`, `i486`.

**Passi** (sostituisci `<arch>` con `aarch64`, `armv7hl` o `i486`):

1. **Clona il repository**
   ```sh
   git clone https://github.com/RootGPT-YouTube/RooTheater-SailfishOS.git
   cd RooTheater-SailfishOS
   ```
2. **Installa la dipendenza di build** nel target dell'SDK (una volta per arch).
   Il percorso HW diretto si linka a `droidmedia`:
   ```sh
   sfdk engine exec sb2 -t SailfishOS-5.0.0.62-<arch>.default \
        -m sdk-install -R zypper -n in droidmedia-devel
   ```
3. **Vendorizza FFmpeg** — `.a` statiche PIC, compilate LGPL (niente
   `--enable-gpl`, niente x264):
   ```sh
   bash scripts/build-ffmpeg.sh <arch>      # → ffmpeg/<arch>/lib/*.a
   ```
4. **Vendorizza libVLC** — `.so` + plugin bundlati; lunga, compila i contrib di
   VLC (incluso il suo FFmpeg) da sorgente:
   ```sh
   bash scripts/build-libvlc.sh <arch>      # → vlc/<arch>/lib + vlc/<arch>/lib/vlc/plugins
   ```
5. **Compila l'RPM**:
   ```sh
   sfdk -c target=SailfishOS-5.0.0.62-<arch> build
   # → RPMS/harbour-rootheater-<versione>-1.<arch>.rpm
   ```
6. **Installa sul dispositivo** (copia l'RPM, poi sul telefono):
   ```sh
   sudo pkcon install-local --allow-untrusted harbour-rootheater-<versione>-1.<arch>.rpm
   ```

**Note**
- Il `.pro` abilita il layer libVLC solo se esiste `vlc/<arch>/lib/libvlc.so` e
  il layer droidmedia solo se `packagesExist(droidmedia)`: se manca un pezzo
  vendorizzato l'app si compila comunque, ma **senza quel layer**. Controlla i
  `message(...)` di qmake ("libvlc backend enabled…", "droidmedia HW path
  enabled") per confermare che ogni layer sia attivo.
- Su **i486** gli script disabilitano automaticamente l'assembly x86 (il target
  SFOS i486 non ha nasm/yasm).
- Per un rilascio completo a 3 architetture, ripeti i passi 2–5 per ogni `<arch>`.

## License

GPL-3.0 © 2026 RootGPT. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
