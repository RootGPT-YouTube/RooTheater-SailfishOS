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

# PROFILO COMPLETO (dalla 1.9.0): stessi codec/demuxer/accessi di VLC desktop.
# Prima (fino alla 1.8.0) la build era "lean" (contrib = ffmpeg+gnutls+dvbpsi):
# niente AV1 (dav1d), niente mkv/ogg nativi, niente libass. Ora i contrib sono
# quasi tutti, e restano fuori SOLO:
#  - interfacce grafiche e uscite video di VLC (il video va gia' a RooTheater);
#  - fdk-aac (licenza Fraunhofer incompatibile con la GPL; l'AAC lo fa ffmpeg);
#  - libdvdcss / aacs / bdplus / aribb25 (aggirano protezioni: non distribuibili
#    in UE/IT). dvdread/bluray restano, per i dischi non protetti; dvdread carica
#    da solo libdvdcss a runtime se l'utente l'ha installata per conto suo.
# ⛔ zvbi NO: pdc.c e packet-830.c (linkati nel plugin) sono "GPL version 2"
#    SENZA "or later" ⇒ incompatibili con la GPL-3.0 dell'app. Il teletext lo fa
#    telx, il decoder interno di VLC (GPLv2+). Controllo fatto su tutti i contrib
#    (file GPL senza "later"): restano solo x265/md5 (GPL senza versione = va
#    bene qualsiasi) e faad2/aacDECdrop (frontend Windows, non linkato).
# Licenze: l'insieme e' GPLv2+ (x264/x265/faad2/a52/dca/libmpeg2...), compatibile
# con la GPL-3.0 di RooTheater. Elenco e testi in licenses/ + NOTICE.md.
# Cartelle separate (-full) per non toccare la build lean usata fino alla 1.8.0.

ARCH="${1:-aarch64}"
STEP="${2:-all}"          # all | contrib | vlc | vendor  (per riprendere a fasi)
case "$ARCH" in
    aarch64) HOST="aarch64-meego-linux-gnu" ;;
    armv7hl) HOST="armv7hl-meego-linux-gnueabi" ;;
    i486)    HOST="i486-meego-linux-gnu" ;;
    *) echo "arch non supportata: $ARCH"; exit 1 ;;
esac
# Stesso target dell'app (il telefono gira 5.1+). ⛔ MAI `sfdk config target=`:
# non ha effetto fra un comando e l'altro; solo `-c target=` su ogni chiamata.
SFOS_TARGET="SailfishOS-5.1.0.11-$ARCH"

SFDK="${SFDK:-$HOME/SailfishOS/bin/sfdk}"
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
VER="3.0.21"
B="$PROJ/_libvlc_build"
SRC="$B/vlc-$VER"
SUF="-full"
CONTRIB="$SRC/contrib/sfos-$ARCH$SUF"
PREFIX="$B/prefix-$ARCH$SUF"      # contrib install prefix (sysroot-style)
STAGE="$B/stage-$ARCH$SUF"        # libvlc install stage
BUILD="$B/build-$ARCH$SUF"
TOOLS="$B/tools/bin"              # meson (non c'e' nel build-shell): vedi sotto
LOG="$B/logs-$ARCH$SUF"
mkdir -p "$B" "$LOG"
cd "$B"
[ -f vlc-$VER.tar.xz ] || curl -fsSL -o vlc-$VER.tar.xz \
    "https://download.videolan.org/pub/videolan/vlc/$VER/vlc-$VER.tar.xz"
[ -d "$SRC" ] || tar xf vlc-$VER.tar.xz

# meson: dav1d (e altri) si configurano con meson, assente nel build-shell. E'
# puro Python: tarball ufficiale + lanciatore in tools/bin (il container dell'SDK
# vede _libvlc_build perche' sta sotto la home dell'utente).
if [ ! -x "$TOOLS/meson" ]; then
    mkdir -p "$TOOLS"; ( cd "$B/tools"
    curl -fsSL -o meson-1.5.2.tar.gz https://github.com/mesonbuild/meson/releases/download/1.5.2/meson-1.5.2.tar.gz
    tar xf meson-1.5.2.tar.gz )
    printf '#!/bin/sh\nexec python3 %s/meson-1.5.2/meson.py "$@"\n' "$B/tools" > "$TOOLS/meson"
    chmod +x "$TOOLS/meson"
fi

sfdk_shell() { (cd "$PROJ" && "$SFDK" -c target="$SFOS_TARGET" build-shell bash -c "$1"); }

# ── 1) contrib (librerie terze) da sorgente ──────────────────────────────────
# Prerequisito nel target (una volta per arch): gettext-devel, per `autopoint`
# (libgpg-error rigenera il configure). Senza, gcrypt fallisce:
#   sfdk engine exec sb2 -t SailfishOS-5.1.0.11-<arch>.default -m sdk-install -R \
#        zypper -n in gettext-devel
# Il target i486 e' piu' spoglio: servono anche git (gcrypt fa un commit
# fittizio), ninja (meson), gperf, bison, flex e nasm (asm x86 di dav1d/x264/vpx):
#        zypper -n in gettext-devel git ninja gperf bison flex nasm
# Un pacchetto alla volta, per NOME (make trascina le dipendenze): un guasto non
# ferma gli altri, finisce in $LOG/contrib-<pkg>.log e nell'elenco FALLITI.
CONTRIB_PKGS="${CONTRIB_PKGS:-ffmpeg gnutls gcrypt dvbpsi dav1d vpx ogg vorbis opus flac theora \
 speex speexdsp a52 dca faad2 mpg123 libmpeg2 twolame lame x264 x265 ebml matroska \
 fribidi ass kate modplug gme sidplay2 libxml2 taglib live555 libarchive \
 dvdread dvdnav bluray aribb24 postproc soxr samplerate mysofa spatialaudio png jpeg \
 srt ssh2 smb2 nfs upnp libdsm mpcdec openjpeg}"
build_contrib() {
# i486: niente nasm/yasm nel target e l'asm inline di ffmpeg 4.4.4 non si
# assembla con il gas del target ⇒ --disable-x86asm --disable-inline-asm.
if [ "$ARCH" = "i486" ]; then
    sed -i -E 's/^FFMPEGCONF \+= --arch=x86( --disable-x86asm)?$/FFMPEGCONF += --arch=x86 --disable-x86asm --disable-inline-asm/' \
        "$SRC/contrib/src/ffmpeg/rules.mak"
fi
# ffmpeg 4.4.4 su ARM32: i binutils del target 5.1 rifiutano le etichette locali
# "01:"/"01b" di mlpdsp_armv5te.S ("junk at end of line"). Stessa correzione di
# upstream (01 -> 1), applicata subito dopo l'estrazione. Idempotente.
grep -q 'mlpdsp_armv5te' "$SRC/contrib/src/ffmpeg/rules.mak" || \
    sed -i 's|^\t$(APPLY) $(SRC)/ffmpeg/armv7_fixup.patch$|&\n\tsed -i -e "s/^01:/1:/" -e "s/bne     01b/bne     1b/" $@-$(FFMPEG_VERSION)/libavcodec/arm/mlpdsp_armv5te.S|' \
        "$SRC/contrib/src/ffmpeg/rules.mak"
# x265 2.9 su ARM32 compila con -mcpu=native (in cross il wrapper lo rende
# "-march=" vuoto ⇒ errore): al suo posto -march=armv7-a (hard-float, NEON
# scelto da x265 stesso). Applicato subito dopo l'estrazione. Idempotente.
grep -q 'mcpu=native' "$SRC/contrib/src/x265/rules.mak" || \
    sed -i 's|^\t$(APPLY) $(SRC)/x265/x265-pkg-libs.patch$|&\n\tsed -i "s/-mcpu=native/-march=armv7-a/" $(UNPACK_DIR)/source/CMakeLists.txt|' \
        "$SRC/contrib/src/x265/rules.mak"
# ...e su ARM32 senza assembly: asm-primitives.cpp di x265 2.9 non compila col
# gcc del target ("incompatible types in assignment"). x265 e' solo un encoder
# (registrazione futura): la velocita' su armv7hl conta poco.
grep -q 'ENABLE_ASSEMBLY' "$SRC/contrib/src/x265/rules.mak" || \
    sed -i 's|-DENABLE_CLI=OFF$|-DENABLE_CLI=OFF $(if $(filter arm,$(ARCH)),-DENABLE_ASSEMBLY=OFF)|' \
        "$SRC/contrib/src/x265/rules.mak"
# Senza assembly, cpu.cpp chiamerebbe comunque i test NEON in asm (HAVE_ARMV6=1
# fisso nel CMakeLists per ogni ARM) ⇒ undefined x265_cpu_fast_neon_mrc_test.
# Su ARM32 l'asm e' sempre spento (sopra), quindi HAVE_ARMV6=0. (aarch64 non e'
# "ARM" per x265 2.9: non lo tocca.)
grep -q 'HAVE_ARMV6' "$SRC/contrib/src/x265/rules.mak" || \
    sed -i 's|^\t$(APPLY) $(SRC)/x265/x265-pkg-libs.patch$|&\n\tsed -i "s/-DHAVE_ARMV6=1)/-DHAVE_ARMV6=0)/" $(UNPACK_DIR)/source/CMakeLists.txt|' \
        "$SRC/contrib/src/x265/rules.mak"
# dvdread SENZA dvdcss: la regola dei contrib lo lega per forza (DEPS + flag).
# Come Fedora: dvdread legge i DVD non cifrati e, se presente, carica libdvdcss
# da solo a runtime. Idempotente.
sed -i -e 's/^DEPS_dvdread = dvdcss$/DEPS_dvdread =/' \
       -e 's/^\.dvdread: dvdread \.dvdcss$/.dvdread: dvdread/' \
       -e 's/ --with-libdvdcss//' "$SRC/contrib/src/dvdread/rules.mak"
# bluray: i menu BD-J vogliono Java+ant (assenti, e sul telefono inutili).
grep -q 'disable-bdjava-jar' "$SRC/contrib/src/bluray/rules.mak" || \
    sed -i 's/^\(BLURAY_CONF = --disable-examples  \\\)$/\1\n              --disable-bdjava-jar \\/' \
        "$SRC/contrib/src/bluray/rules.mak"
# freetype2 / harfbuzz / fontconfig: quelli DI SISTEMA (ci sono su ogni SFOS, li
# usa Qt). Un fontconfig statico dei contrib cercherebbe la configurazione sotto
# $PREFIX/etc e sul telefono non troverebbe nessun font. Questo rules.mak viene
# incluso DOPO main.mak (glob src/*/rules.mak): li dichiara "trovati" e rimette
# il pkg-config del sysroot in coda a quello dei contrib.
mkdir -p "$SRC/contrib/src/zz-sfos-system"
cat > "$SRC/contrib/src/zz-sfos-system/rules.mak" <<'MK'
# SFOS: librerie prese dal sistema invece che compilate (vedi build-libvlc.sh)
PKGS_FOUND += freetype2 harfbuzz fontconfig
PKG_CONFIG_LIBDIR := /usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig
export PKG_CONFIG_LIBDIR
MK
local FAILED=""
sfdk_shell "
cd '$SRC/contrib'
mkdir -p 'sfos-$ARCH$SUF' && cd 'sfos-$ARCH$SUF'
[ -f Makefile ] || ../bootstrap --host='$HOST' --prefix='$PREFIX'
" > "$LOG/contrib-bootstrap.log" 2>&1
for p in $CONTRIB_PKGS; do
    printf '  contrib %-14s ' "$p"
    if sfdk_shell "
set -e
cd '$CONTRIB'
export PATH='$TOOLS':\$PATH
export CC=gcc CXX=g++ AR=ar RANLIB=ranlib LD=ld STRIP=strip NM=nm
export PKG_CONFIG=pkg-config
# sidplay2: C++ del 2007, il gcc attuale rifiuta i narrowing char->int8_t.
[ '$p' = sidplay2 ] && export CXXFLAGS='-Wno-narrowing'
make -j\$(nproc) .$p
" > "$LOG/contrib-$p.log" 2>&1; then echo ok; else echo FALLITO; FAILED="$FAILED $p"; fi
done
echo "contrib FALLITI:${FAILED:- nessuno}" | tee "$LOG/contrib-failed.txt"
}

# ── 2) libvlc core, set di moduli COMPLETO ───────────────────────────────────
build_vlc() {
sfdk_shell "
set -e
cd '$SRC'
export CC=gcc CXX=g++ AR=ar RANLIB=ranlib LD=ld STRIP=strip NM=nm
# BUILDCC: i tool helper di VLC girano sulla macchina di build; nel sb2 'gcc' e'
# il cross, 'host-gcc' e' il compilatore nativo eseguibile.
export BUILDCC=host-gcc
# Privacy: -ffile-prefix-map toglie i path assoluti della macchina di build.
export CFLAGS=\"-ffile-prefix-map=$SRC=. -ffile-prefix-map=$BUILD=. -ffile-prefix-map=$PREFIX=. \${CFLAGS:-}\"
export CXXFLAGS=\"\$CFLAGS\"
# Header e librerie dei contrib senza file .pc (a52, faad2, libmpeg2...): VLC li
# cerca con AC_CHECK_HEADERS/LIB, che vedono solo questi percorsi.
export CPPFLAGS=\"-I$PREFIX/include \${CPPFLAGS:-}\"
export LDFLAGS=\"-L$PREFIX/lib \${LDFLAGS:-}\"
# PKG_CONFIG_PATH additivo: i contrib prima, il sysroot (libpulse, freetype...) dopo.
export PKG_CONFIG_PATH='$PREFIX/lib/pkgconfig'
# I contrib sono statici e VLC interroga pkg-config senza --static: senza le
# dipendenze transitive i plugin non linkano (undefined nettle_*, gpg_err_*...).
export PKG_CONFIG='pkg-config --static'
export GNUTLS_CFLAGS=\"-I'$PREFIX'/include\"
export GNUTLS_LIBS=\"\$(pkg-config --static --libs gnutls)\"
mkdir -p '$BUILD' && cd '$BUILD'
'$SRC'/configure --host='$HOST' --prefix=/usr \
  --disable-vlc --disable-nls --disable-update-check \
  --disable-lua --disable-qt --disable-skins2 --disable-ncurses \
  --disable-xcb --disable-wayland --disable-x11 --disable-glx --disable-egl --disable-gles2 \
  --without-x --disable-vdpau --disable-libva --disable-sdl-image --disable-caca \
  --disable-alsa --disable-jack --enable-pulse \
  --disable-mtp --disable-udev --disable-dbus --disable-notify \
  --disable-secret --disable-libsecret --disable-kwallet \
  --disable-chromecast --disable-microdns --disable-avahi \
  --disable-libplacebo --disable-goom --disable-projectm --disable-vsxu \
  --disable-fluidsynth --disable-fluidlite --disable-decklink --disable-crystalhd \
  --disable-dvdcss --disable-aribb25 --disable-fdkaac --disable-medialibrary \
  --disable-zvbi --enable-telx \
  --enable-sout --enable-vlm \
  --enable-shared --disable-static \
  --enable-avcodec --enable-avformat --enable-swscale --enable-postproc \
  --enable-gnutls --enable-dvbpsi --enable-libgcrypt \
  --enable-dav1d --enable-vpx --enable-ogg --enable-vorbis --enable-opus --enable-flac \
  --enable-theora --enable-speex --enable-a52 --enable-dca --enable-faad \
  --enable-mpg123 --enable-libmpeg2 --enable-twolame --enable-x264 --enable-x265 \
  --enable-mkv --enable-libass --enable-freetype --enable-fribidi --enable-harfbuzz \
  --enable-fontconfig --enable-kate --enable-mod --enable-gme --enable-sid \
  --enable-libxml2 --enable-taglib --enable-live555 --enable-archive \
  --enable-dvdread --enable-dvdnav --enable-bluray --enable-aribb24 \
  --enable-soxr --enable-samplerate --enable-spatialaudio --enable-png --enable-jpeg \
  --enable-srt --enable-sftp --enable-smb2 --enable-nfs --enable-upnp --enable-dsm \
  --enable-mpc
make -j\$(nproc)
rm -rf '$STAGE'
# Install MIRATO per-dir (share/ fallisce con --disable-vlc; i moduli NON via
# make install: il relink di libtool nel cross tronca il set in silenzio).
for d in src lib include; do
  make -C \"\$d\" install DESTDIR='$STAGE' || true
done
mkdir -p '$STAGE/usr/lib/vlc/plugins'
cp -f '$BUILD/modules/.libs/'lib*_plugin.so '$STAGE/usr/lib/vlc/plugins/'
" 2>&1 | tee "$LOG/vlc.log"
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
    if [ -f "$BUILD/modules/.libs/libvlc_pulse.so.0.0.0" ]; then
        mkdir -p "$DST/lib/vlc"
        cp -f "$BUILD/modules/.libs/libvlc_pulse.so.0.0.0" "$DST/lib/vlc/libvlc_pulse.so.0"
    fi
    # header pubblici (una volta)
    if [ ! -d "$PROJ/vlc/include/vlc" ]; then
        mkdir -p "$PROJ/vlc/include"
        cp -a "$STAGE/usr/include/vlc" "$PROJ/vlc/include/"
    fi
    # Privacy: rimuovi l'RPATH che libtool cabla verso la build dir. Resta come
    # stringa in .dynstr (leak del path /home/<user>/...) anche dopo lo strip.
    # --set-rpath '' RISCRIVE .dynstr (a differenza di --remove-rpath, che lascia
    # la stringa orfana). patchelf è un tool host (pip wheel: ~/.local/bin).
    local PATCHELF; PATCHELF="$(command -v patchelf || echo "$HOME/.local/bin/patchelf")"
    find "$DST/lib" -type f -name '*.so*' -exec "$PATCHELF" --set-rpath '' {} \; 2>/dev/null || true
    # Strip dei simboli di debug (eu-strip: arch-agnostico, host). Senza, i 4
    # plugin ffmpeg-based pesano 78-100MB L'UNO e il bundle installato supera i
    # 400MB su / del device (~70MB da strippato). Solo file reali, non i symlink.
    find "$DST/lib" -type f -name '*.so*' -exec eu-strip {} \; 2>/dev/null || true
    # Privacy: scrub del path di build che resta nelle stringhe di configure-line
    # (ffmpeg av_configuration() nei plugin av*, VLC CONFIGURE_LINE in libvlccore) —
    # non le tocca né prefix-map né strip. Sostituzione a LUNGHEZZA COSTANTE (non
    # sposta gli offset ELF) di $PROJ con un placeholder: sicuro, sono stringhe
    # solo diagnostiche (vlc --version / av diag), nessun uso funzionale a runtime.
    python3 - "$DST" "$PROJ" <<'PY' || true
import sys,glob,os
dst,proj=sys.argv[1],sys.argv[2].encode()
repl=b'/rootheater-build'.ljust(len(proj),b'_')[:len(proj)]
for f in glob.glob(dst+'/lib/**/*.so*',recursive=True):
    if os.path.islink(f): continue
    b=open(f,'rb').read()
    if proj in b: open(f,'wb').write(b.replace(proj,repl))
PY
    echo "=== vendored -> vlc/$ARCH ==="
    ls -lh "$DST/lib/"libvlc*.so* 2>/dev/null
    echo "plugin: $(find "$DST/lib/vlc/plugins" -name '*.so' 2>/dev/null | wc -l)"
}

case "$STEP" in
    contrib) build_contrib ;;
    vlc)     build_vlc; vendor ;;
    vendor)  vendor ;;
    all)     build_contrib; build_vlc; vendor ;;
esac

echo "=== libvlc stage: $STAGE/usr ==="
ls "$STAGE/usr/lib/"libvlc*.so* 2>/dev/null && echo "libvlc OK" || echo "(libvlc non ancora prodotta — vedi log)"
