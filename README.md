# RooTheater

A multimedia player for SailfishOS — hardware-accelerated playback of local
files and network streams.

- **App name:** RooTheater
- **Author:** RootGPT
- **Version:** 0.1.0
- **Platform:** SailfishOS 5.0+
- **License:** GPLv3 (see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md))

## English

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
