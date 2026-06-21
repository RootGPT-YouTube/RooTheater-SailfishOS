#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# build-ffmpeg.sh — cross-compila lo stack ffmpeg come LIBRERIE STATICHE PIC,
# da linkare dentro il binario PIE di RooTheater. ffmpeg qui è la fondazione del
# media-engine facade: (1) demux dei container (MP4/MKV/TS/AVI/HLS...) per
# estrarre il bitstream elementare H.264/HEVC/VP9 che alimenterà droidmedia
# (v0.3); (2) probe di codec/tracce per la selezione capability-driven del
# backend; (3) decode software di fallback.
#
# Differenze rispetto alla ricetta di RooTelegram (che builda un CLI statico per
# il transcoding): qui --enable-pic (gli .a vanno in un eseguibile PIE),
# --disable-programs (ci serve la libreria, non il binario), NIENTE x264/encoder
# (restiamo LGPL, non GPL), config "player" con demuxer ampi + protocolli di
# rete + decoder SW di fallback.
#
# Output: ffmpeg/<arch>/lib/lib{avformat,avcodec,avutil,swscale,swresample}.a
#         ffmpeg/<arch>/include/...   (header dell'ABI 7.0.2, usati in compile)
#
# Uso:  bash scripts/build-ffmpeg.sh [aarch64|armv7hl|i486]   (default: aarch64)
# Convenzione di progetto: si sviluppa su aarch64; armv7hl/i486 solo al rilascio.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ARCH="${1:-aarch64}"
FFMPEG_EXTRA=""
case "$ARCH" in
    aarch64) SFOS_TARGET="SailfishOS-5.0.0.62-aarch64" ;;
    armv7hl) SFOS_TARGET="SailfishOS-5.0.0.62-armv7hl" ;;
    # i486: niente nasm/yasm nel target -> disabilita l'asm x86.
    i486)    SFOS_TARGET="SailfishOS-5.0.0.62-i486"; FFMPEG_EXTRA="--disable-x86asm" ;;
    *) echo "arch non supportata: $ARCH (usa aarch64|armv7hl|i486)"; exit 1 ;;
esac

SFDK="${SFDK:-$HOME/SailfishOS/bin/sfdk}"
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
B="$PROJ/_ffmpeg_build/$ARCH"
FFMPEG_VER="7.0.2"
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VER}.tar.xz"
# Riusa il tarball già scaricato in RooTelegram, se presente (evita il download).
RT_TARBALL="$HOME/Developing/SailfishOS/RooTelegram/_ffmpeg_build/ffmpeg.tar.xz"

mkdir -p "$B"
cd "$B"
if [ ! -f ffmpeg.tar.xz ]; then
    if [ -f "$RT_TARBALL" ]; then cp "$RT_TARBALL" ffmpeg.tar.xz
    else curl -fsSL -o ffmpeg.tar.xz "$FFMPEG_URL"; fi
fi
rm -rf "ffmpeg-${FFMPEG_VER}"
tar xf ffmpeg.tar.xz

# NB: sfdk va invocato dalla ROOT del build tree (dove sta il .pro), non da $B.
(cd "$PROJ" && "$SFDK" config --global target="$SFOS_TARGET")

# ffmpeg come librerie statiche PIC, config "player completo":
#  - demuxer: container comuni + HLS/DASH per stream remoti
#  - protocolli: file/pipe + rete (http/https/tcp/udp/rtp/hls/tls via openssl)
#  - decoder: i codec garantiti (h264/hevc/vp9) + SW fallback comuni
#  - parser/bsf: per estrarre l'elementary stream verso droidmedia
#  - swscale/swresample: conversione pixel/sample per il fallback SW
(cd "$PROJ" && "$SFDK" build-shell bash -c "
set -e
cd '$B/ffmpeg-${FFMPEG_VER}'
./configure \
  --enable-version3 --enable-small \
  --enable-static --disable-shared --enable-pic \
  --disable-debug --disable-doc --disable-htmlpages --disable-manpages --disable-txtpages \
  --disable-programs --disable-ffplay --disable-ffprobe --disable-ffmpeg \
  --disable-autodetect \
  --disable-everything \
  --enable-network --enable-openssl \
  --enable-protocol=file,pipe,http,https,tcp,udp,rtp,hls,crypto,tls,data \
  --enable-demuxer=mov,matroska,avi,mpegts,mpegps,flv,asf,wav,mp3,flac,ogg,aac,ac3,hls,dash,h264,hevc,mjpeg,image2,concat \
  --enable-decoder=h264,hevc,vp8,vp9,mpeg2video,mpeg4,mjpeg,aac,mp3,ac3,vorbis,opus,flac,pcm_s16le,pcm_u8,pcm_s16be \
  --enable-parser=h264,hevc,vp8,vp9,mpeg4video,mpegvideo,aac,ac3,opus,flac,mjpeg \
  --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc,extract_extradata \
  --enable-swscale --enable-swresample \
  $FFMPEG_EXTRA \
  --extra-libs='-lpthread -lm -ldl'
make -j\$(nproc)
# 'make install' in uno stage DESTDIR: installa SOLO gli header pubblici (le API),
# non gli header interni dell'albero sorgente. Da lì raccogliamo .a + include.
rm -rf '$B/stage'
make install DESTDIR='$B/stage'
")

STAGE="$B/stage/usr/local"

# Raccolta artefatti: .a per-arch.
DST="$PROJ/ffmpeg/$ARCH"
rm -rf "$DST"
mkdir -p "$DST/lib"
for L in libavformat libavcodec libavutil libswscale libswresample; do
    cp "$STAGE/lib/$L.a" "$DST/lib/$L.a"
done

# Header pubblici (identici per tutte le arch a parte avconfig.h, trascurabile:
# li versioniamo una volta sola sotto ffmpeg/include).
INC="$PROJ/ffmpeg/include"
if [ ! -d "$INC/libavformat" ]; then
    mkdir -p "$INC"
    cp -r "$STAGE/include/." "$INC/"
fi

echo "OK -> ffmpeg/$ARCH/lib/*.a"
ls -lh "$DST/lib/"
