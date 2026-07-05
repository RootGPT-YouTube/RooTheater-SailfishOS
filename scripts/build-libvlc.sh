#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# build-libvlc.sh — cross-compila libvlc/libvlccore 3.0.x (+ i plugin necessari)
# per Sailfish OS. libvlc è il Layer 3 del motore (copertura di protocolli/codec/
# sottotitoli esotici che gst-droid+ffmpeg non gestiscono). 3.x è l'ultima serie
# con i callback vmem (frame in RAM) usabili per il render in Qt Quick: la 4.x ha
# i callback GL ma è sperimentale.
#
# Strategia: si compila l'albero `contrib` di VLC DA SORGENTE (il triplet SFOS
# aarch64-meego-linux-gnu non ha contrib prebuilt scaricabili), poi libvlc con un
# set di moduli "lean" (niente GUI/qt/skins/lua), output video = vmem, audio via
# il modulo pulse di sistema. Output bundlato (NON static come ffmpeg): le .so
# vanno in /usr/share/<app>/lib + i plugin in .../lib/vlc/plugins.
#
# Build dentro la Sailfish SDK: `sfdk build-shell` (lì `gcc` è già il cross).
# Uso:  bash scripts/build-libvlc.sh [aarch64|armv7hl|i486] [stage|contrib|vlc]
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ARCH="${1:-aarch64}"
STEP="${2:-all}"          # all | contrib | vlc  (per riprendere a fasi)
case "$ARCH" in
    aarch64) SFOS_TARGET="SailfishOS-5.0.0.62-aarch64"; HOST="aarch64-meego-linux-gnu" ;;
    armv7hl) SFOS_TARGET="SailfishOS-5.0.0.62-armv7hl"; HOST="armv7hl-meego-linux-gnueabi" ;;
    i486)    SFOS_TARGET="SailfishOS-5.0.0.62-i486";    HOST="i486-meego-linux-gnu" ;;
    *) echo "arch non supportata: $ARCH"; exit 1 ;;
esac

SFDK="${SFDK:-$HOME/SailfishOS/bin/sfdk}"
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
VER="3.0.21"
B="$PROJ/_libvlc_build"
SRC="$B/vlc-$VER"
CONTRIB="$SRC/contrib/sfos-$ARCH"
PREFIX="$B/prefix-$ARCH"          # contrib install prefix (sysroot-style)
STAGE="$B/stage-$ARCH"            # libvlc install stage

mkdir -p "$B"
cd "$B"
[ -f vlc-$VER.tar.xz ] || curl -fsSL -o vlc-$VER.tar.xz \
    "https://download.videolan.org/pub/videolan/vlc/$VER/vlc-$VER.tar.xz"
[ -d "$SRC" ] || tar xf vlc-$VER.tar.xz

(cd "$PROJ" && "$SFDK" config --global target="$SFOS_TARGET")

# ── 1) contrib (librerie terze) da sorgente ──────────────────────────────────
# TRIM "lean": NON costruiamo l'intero set di default dei contrib (decine di
# librerie, molte inutili su SFOS — alsa/salsa, encoder x264/x262, roba Windows
# — e alcune richiedono git/nasm assenti nel build-shell). Costruiamo solo i
# pacchetti che danno la copertura codec di libvlc, per NOME, lasciando che make
# trascini le loro dipendenze (es. .ffmpeg → zlib, gsm). ffmpeg 4.4.4 arriva dal
# release tarball https (il git è solo nel ramo USE_LIBAV inattivo).
# Esportiamo i tool cross espliciti: nel build-shell `gcc` è il cross, ma i
# Makefile dei contrib costruiscono i nomi come $(HOST)-gcc, che NON esistono.
# .gnutls: TLS client per libvlc. SENZA, libvlc non ha alcun modulo TLS ("TLS
# client plugin not available") e NON apre URL https:// — gli stream HLS/DASH reali
# danno schermo nero. (mbedtls, piu' leggero, NON e' nei contrib di VLC 3.0.21;
# l'unico TLS disponibile e' gnutls.) make trascina le sue deps nettle/gmp/libtasn1;
# i contrib sono statici, quindi gnutls+deps si linkano dentro libgnutls_plugin.so
# e il vendor step lo raccoglie gia' con cp lib*_plugin.so (nessuna .so extra).
# .dvbpsi: serve al demuxer MPEG-TS di libvlc (libts_plugin). SENZA, gli stream
# HLS in TS (il formato IPTV piu' diffuso) falliscono con "Failed to create
# demuxer TS". (L'HLS in fMP4 usa invece libmp4, gia' presente.)
CONTRIB_PKGS="${CONTRIB_PKGS:-.ffmpeg .gnutls .dvbpsi}"
build_contrib() {
# i486: the SFOS target ships no nasm/yasm, so VLC's contrib ffmpeg (x86) needs
# --disable-x86asm (else configure aborts: "nasm/yasm not found"); and its older
# 4.4.4 inline asm doesn't assemble with the target gas (mathops.h: "operand type
# mismatch for shr"), so also --disable-inline-asm. ARM targets use gas fine and
# are untouched. Idempotent (matches the pristine or the already-patched line).
if [ "$ARCH" = "i486" ]; then
    sed -i -E 's/^FFMPEGCONF \+= --arch=x86( --disable-x86asm)?$/FFMPEGCONF += --arch=x86 --disable-x86asm --disable-inline-asm/' \
        "$SRC/contrib/src/ffmpeg/rules.mak"
fi
# sfdk build-shell DEVE girare dalla root del build tree (dove sta il .pro);
# i path interni sono assoluti, quindi il cwd di lavoro non conta.
(cd "$PROJ" && "$SFDK" build-shell bash -c "
set -e
cd '$SRC/contrib'
mkdir -p 'sfos-$ARCH' && cd 'sfos-$ARCH'
export CC=gcc CXX=g++ AR=ar RANLIB=ranlib LD=ld STRIP=strip NM=nm
export PKG_CONFIG=pkg-config
# bootstrap (se non già fatto): genera il Makefile per l'host SFOS
[ -f Makefile ] || ../bootstrap --host='$HOST' --prefix='$PREFIX'
# build mirato dei soli pacchetti richiesti (+ dipendenze risolte da make)
make -j\$(nproc) $CONTRIB_PKGS
")
}

# ── 2) libvlc core, set di moduli lean ───────────────────────────────────────
build_vlc() {
(cd "$PROJ" && "$SFDK" build-shell bash -c "
set -e
cd '$SRC'
[ -x configure ] || ./bootstrap
export CC=gcc CXX=g++ AR=ar RANLIB=ranlib LD=ld STRIP=strip NM=nm
# BUILDCC: VLC compila alcuni tool helper che girano sulla macchina di build.
# Nel sb2 `gcc` è il cross (aarch64); `host-gcc` (i486-meego) è il compilatore
# 'tools' eseguibile nell'ambiente di build → è il nostro compilatore nativo.
export BUILDCC=host-gcc
# PKG_CONFIG_PATH (additivo) per trovare il NOSTRO ffmpeg contrib SENZA perdere
# il path di sistema del sb2 (dove sta libpulse ecc.). NB: usare LIBDIR lo
# sostituirebbe, nascondendo le lib del target.
export PKG_CONFIG_PATH='$PREFIX/lib/pkgconfig'
# gnutls contrib e' statico: VLC usa pkg-config NON-static (solo -lgnutls), e il
# plugin gnutls non linka (undefined nettle_*). Pre-impostiamo GNUTLS_LIBS con le
# deps statiche (gnutls -> hogweed/nettle/gmp); PKG_CHECK_MODULES la tratta come
# variabile precious e salta la propria probe.
export GNUTLS_CFLAGS=\"-I'$PREFIX'/include\"
export GNUTLS_LIBS=\"\$(pkg-config --static --libs gnutls)\"
mkdir -p '$B/build-$ARCH' && cd '$B/build-$ARCH'
'$SRC'/configure --host='$HOST' --prefix=/usr \
  --disable-vlc --disable-nls --disable-update-check \
  --disable-lua --disable-qt --disable-skins2 --disable-ncurses \
  --disable-srt --disable-vnc \
  --disable-xcb --disable-wayland --disable-x11 --disable-glx --disable-egl --disable-gles2 \
  --disable-alsa --enable-pulse \
  --disable-mtp --disable-udev --disable-dbus \
  --disable-sout --disable-vlm \
  --enable-avcodec --enable-swscale \
  --enable-shared --disable-static \
  --without-x \
  --disable-a52 --disable-dca --disable-flac --disable-libmpeg2 \
  --disable-vorbis --disable-tremor --disable-speex --disable-opus --disable-theora \
  --disable-daala --disable-schroedinger --disable-png --disable-jpeg --disable-bpg \
  --disable-x264 --disable-x265 --disable-x26410b --disable-mpg123 --disable-mad \
  --disable-faad --disable-aom --disable-dav1d --disable-twolame --disable-fdkaac \
  --disable-vpx --disable-mod --disable-gme --disable-sid \
  --disable-fluidsynth --disable-fluidlite --disable-zvbi --disable-telx --disable-kate \
  --disable-libass --disable-freetype --disable-fribidi --disable-harfbuzz \
  --disable-fontconfig --disable-svg --disable-svgdec --disable-sdl-image \
  --disable-aribb24 --disable-aribb25 \
  --disable-dvdread --disable-dvdnav --disable-bluray --enable-dvbpsi \
  --disable-live555 --disable-libtar --disable-libxml2 --disable-libarchive \
  --enable-gnutls --disable-libgcrypt --disable-secret --disable-libsecret \
  --disable-chromaprint --disable-caca --disable-goom --disable-projectm --disable-vsxu \
  --disable-libplacebo --disable-jack --disable-chromecast --disable-microdns --disable-upnp
make -j\$(nproc)
rm -rf '$STAGE'
# Install MIRATO per-dir: libvlc (lib/), libvlccore (src/) e gli header (include/).
# Saltiamo 'share/' (fallisce su vlc.appdata.xml, assente con --disable-vlc) e 'bin/'.
for d in src lib include; do
  make -C \"\$d\" install DESTDIR='$STAGE' || true
done
# Plugin: copiati DIRETTAMENTE dall'albero invece di 'make -C modules install'.
# Quell'install rilinka ogni plugin con libtool e nel cross build il relink puo'
# fallire (armv7hl: relink di libavcodec_plugin -> 'undefined reference to
# av_codec_set_pkt_timebase'), abortendo l'install dei moduli e troncando
# SILENZIOSAMENTE il set. VLC linka ogni plugin finale in modules/.libs/; i
# plugin sono self-describing e caricati ricorsivamente via VLC_PLUGIN_PATH, quindi
# una dir flat va bene (le sottocartelle per categoria dell'install sono cosmetiche).
mkdir -p '$STAGE/usr/lib/vlc/plugins'
cp -f '$B/build-$ARCH/modules/.libs/'lib*_plugin.so '$STAGE/usr/lib/vlc/plugins/'
")
}

# ── 3) vendoring: .so + plugin + header nel layout per-arch del repo ──────────
# A differenza di ffmpeg (static), libvlc si bundla: le .so vanno in
# vlc/<arch>/lib, i plugin in vlc/<arch>/lib/vlc/plugins (li carica via
# VLC_PLUGIN_PATH a runtime). Gli header (uguali per arch) una volta in vlc/include.
vendor() {
    local DST="$PROJ/vlc/$ARCH"
    rm -rf "$DST"
    mkdir -p "$DST/lib"
    # libvlc + libvlccore (segui i symlink, copia il file reale + il SONAME)
    cp -a "$STAGE/usr/lib/"libvlc.so* "$DST/lib/" 2>/dev/null || true
    cp -a "$STAGE/usr/lib/"libvlccore.so* "$DST/lib/" 2>/dev/null || true
    # plugin VLC
    if [ -d "$STAGE/usr/lib/vlc/plugins" ]; then
        mkdir -p "$DST/lib/vlc"
        cp -a "$STAGE/usr/lib/vlc/plugins" "$DST/lib/vlc/"
    fi
    # libpulse_plugin.so dipende da libvlc_pulse.so.0 (NON un *_plugin.so, quindi lo
    # step 'stage' coi soli lib*_plugin.so non lo prende). L'app lo preloada da
    # lib/vlc/; senza, il modulo d'uscita pulse non si carica e libVLC è muto.
    if [ -f "$B/build-$ARCH/modules/.libs/libvlc_pulse.so.0.0.0" ]; then
        mkdir -p "$DST/lib/vlc"
        cp -f "$B/build-$ARCH/modules/.libs/libvlc_pulse.so.0.0.0" "$DST/lib/vlc/libvlc_pulse.so.0"
    fi
    # header pubblici (una volta)
    if [ ! -d "$PROJ/vlc/include/vlc" ]; then
        mkdir -p "$PROJ/vlc/include"
        cp -a "$STAGE/usr/include/vlc" "$PROJ/vlc/include/"
    fi
    # Strip dei simboli di debug (eu-strip: arch-agnostico, host). Senza, i 4
    # plugin ffmpeg-based pesano 78-100MB L'UNO e il bundle installato supera i
    # 400MB su / del device (~70MB da strippato). Solo file reali, non i symlink.
    find "$DST/lib" -type f -name '*.so*' -exec eu-strip {} \; 2>/dev/null || true
    echo "=== vendored -> vlc/$ARCH ==="
    ls -lh "$DST/lib/"libvlc*.so* 2>/dev/null
    echo "plugin: $(find "$DST/lib/vlc/plugins" -name '*.so' 2>/dev/null | wc -l)"
}

case "$STEP" in
    contrib) build_contrib ;;
    vlc)     build_vlc; vendor ;;
    all)     build_contrib; build_vlc; vendor ;;
esac

echo "=== libvlc stage: $STAGE/usr ==="
ls "$STAGE/usr/lib/"libvlc*.so* 2>/dev/null && echo "libvlc OK" || echo "(libvlc non ancora prodotta — vedi log)"
