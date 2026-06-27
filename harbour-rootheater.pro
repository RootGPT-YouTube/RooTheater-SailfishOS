# RooTheater — multimedia player for Sailfish OS (libvlc + HW acceleration)
# Started 2026 by RootGPT.
#
# NOTICE:
# Application name defined in TARGET has a corresponding QML filename.
# If TARGET changes, also rename: the root .qml, the .desktop file, the
# desktop icon, and the translation files.

TARGET = harbour-rootheater

# Single source of truth for the version: bump here and rpm/*.{spec,yaml}
# get synced at release. AboutPage reads it via the `appVersion` context
# property exposed by main.cpp.
# NB: use RT_APP_VERSION (not `VERSION`): qmake treats `VERSION` as reserved
# and on the app template truncates it to major.minor when expanded.
RT_APP_VERSION = 0.6.0
VERSION = $$RT_APP_VERSION

CONFIG += sailfishapp sailfishapp_i18n c++17

# v0.1 baseline engine: QtMultimedia (MediaPlayer + VideoOutput). On SFOS this
# routes through gst-droid → hardware-accelerated decode for common formats.
# Layer 2/3 (libvlc) and the custom droidmedia HW path land in later versions.
# concurrent: MediaEngine runs the ffmpeg probe off the GUI thread.
QT += core gui multimedia concurrent dbus

DEFINES += APP_VERSION=\\\"$$RT_APP_VERSION\\\"

SOURCES += src/harbour-rootheater.cpp \
    src/media/MediaProbe.cpp \
    src/media/MediaEngine.cpp \
    src/media/VideoSurface.cpp \
    src/media/CoverImageProvider.cpp \
    src/media/TrackCoverProvider.cpp \
    src/media/TagReader.cpp \
    src/media/TrackIndexer.cpp \
    src/media/StorageRoots.cpp \
    src/media/MediaGalleryModel.cpp \
    src/media/FileOperations.cpp \
    src/media/ImageEditor.cpp \
    src/media/OpenHandler.cpp

HEADERS += src/media/MediaProbe.h \
    src/media/MediaEngine.h \
    src/media/VideoSurface.h \
    src/media/CoverImageProvider.h \
    src/media/TrackCoverProvider.h \
    src/media/TagReader.h \
    src/media/TrackIndexer.h \
    src/media/StorageRoots.h \
    src/media/MediaGalleryModel.h \
    src/media/FileOperations.h \
    src/media/ImageEditor.h \
    src/media/OpenHandler.h \
    src/media/CoverState.h

# License compliance: the GPLv3 text (and, as bundled libs land, their
# LGPL/GPL/BSD texts) must reach whoever receives the RPM. AboutPage points
# users to /usr/share/harbour-rootheater/licenses/.
licenses.files = $$PWD/LICENSE $$PWD/NOTICE.md
licenses.path = /usr/share/$${TARGET}/licenses
INSTALLS += licenses

# Secondary NoDisplay .desktop carrying the Sailfish content-action ("open/share
# with") hooks for media MIME types → D-Bus openUrl on our app service.
openurl_desktop.files = $$PWD/harbour-rootheater-open-url.desktop
openurl_desktop.path = /usr/share/applications
INSTALLS += openurl_desktop

# ffmpeg is always linked (static facade, scripts/build-ffmpeg.sh) → its LGPL
# texts ship unconditionally. (Built without --enable-gpl/x264, so LGPL only.)
ffmpeglicenses.files = $$files($$PWD/licenses/ffmpeg/*)
ffmpeglicenses.path = /usr/share/$${TARGET}/licenses/ffmpeg
INSTALLS += ffmpeglicenses

# droidmedia (Apache-2.0) is linked for the HW path → ship its license too.
droidmedialicenses.files = $$files($$PWD/licenses/droidmedia/*)
droidmedialicenses.path = /usr/share/$${TARGET}/licenses/droidmedia
INSTALLS += droidmedialicenses

DISTFILES += LICENSE \
    qml/harbour-rootheater.qml \
    qml/cover/CoverPage.qml \
    qml/pages/MainPage.qml \
    qml/pages/PlayerPage.qml \
    qml/pages/AboutPage.qml \
    qml/pages/GalleryPage.qml \
    qml/pages/FolderContentPage.qml \
    qml/pages/ImageViewerPage.qml \
    qml/pages/ImageEditorPage.qml \
    qml/pages/PinchZoom.qml \
    qml/pages/SegmentSelector.qml \
    qml/pages/TagsPage.qml \
    qml/pages/PlaylistBuilderPage.qml \
    qml/pages/PlaylistsPage.qml \
    qml/pages/CoverPickerPage.qml \
    qml/images/rootgpt-avatar.png \
    qml/images/harbour-rootheater.svg \
    harbour-rootheater-open-url.desktop \
    rpm/harbour-rootheater.spec \
    rpm/harbour-rootheater.yaml \
    rpm/harbour-rootheater.changes \
    translations/*.ts \
    harbour-rootheater.desktop

SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172 256x256

# Translations: keep en as the source/reference, it as the primary locale.
TRANSLATIONS += translations/harbour-rootheater-en.ts \
                translations/harbour-rootheater-it.ts

# Per-arch label (used later by the libvlc/droidmedia backends that ship
# arch-specific prebuilt libs, mirroring RooTelegram's layout).
equals(QT_ARCH, arm) {
    message(Building ARM)
    TARGET_ARCHITECTURE = armv7hl
}
equals(QT_ARCH, i386) {
    message(Building i486)
    TARGET_ARCHITECTURE = i486
}
equals(QT_ARCH, arm64) {
    message(Building aarch64)
    TARGET_ARCHITECTURE = aarch64
}

# ── ffmpeg (engine facade foundation) ────────────────────────────────────────
# We link our own ffmpeg 7.0.2 statically (PIC .a built per-arch by
# scripts/build-ffmpeg.sh) — see the engine architecture notes. Static link ⇒
# nothing to bundle, no RPATH, no spec requires/provides excludes for ffmpeg.
# Headers are shared across archs under ffmpeg/include; the .a are per-arch.
INCLUDEPATH += $$PWD/ffmpeg/include
FFMPEG_LIBDIR = $$PWD/ffmpeg/$${TARGET_ARCHITECTURE}/lib
exists($$FFMPEG_LIBDIR/libavformat.a) {
    # --start-group/--end-group resolves the inter-library back-references
    # (avformat↔avcodec↔avutil, swscale/swresample→avutil) without hand-tuning
    # link order. Trailing system deps: openssl (https/tls), zlib, pthread/m/dl.
    LIBS += -Wl,--start-group \
            $$FFMPEG_LIBDIR/libavformat.a \
            $$FFMPEG_LIBDIR/libavcodec.a \
            $$FFMPEG_LIBDIR/libswscale.a \
            $$FFMPEG_LIBDIR/libswresample.a \
            $$FFMPEG_LIBDIR/libavutil.a \
            -Wl,--end-group \
            -lssl -lcrypto -lz -lpthread -lm -ldl
} else {
    error(ffmpeg .a mancanti per $${TARGET_ARCHITECTURE}: esegui scripts/build-ffmpeg.sh $${TARGET_ARCHITECTURE})
}

# ── libvlc (Layer 3 — exotic codec/protocol coverage) ────────────────────────
# Unlike ffmpeg, libvlc is BUNDLED: libvlc/libvlccore .so + the VLC plugins ship
# in /usr/share/<app>/lib (found via the auto RPATH) and .../lib/vlc/plugins
# (found via VLC_PLUGIN_PATH, set by VlcBackend). Built per-arch by
# scripts/build-libvlc.sh; the block is gated on the vendored lib being present
# so the app still builds before libvlc has been cross-compiled for an arch.
VLC_LIBDIR = $$PWD/vlc/$${TARGET_ARCHITECTURE}/lib
exists($$VLC_LIBDIR/libvlc.so) {
    message(libvlc backend enabled for $${TARGET_ARCHITECTURE})
    DEFINES += HAVE_LIBVLC
    INCLUDEPATH += $$PWD/vlc/include
    SOURCES += src/media/VlcBackend.cpp
    HEADERS += src/media/VlcBackend.h
    # -lvlccore esplicito: libvlc.so referenzia simboli di libvlccore (dep
    # transitiva) che il cross-ld non risolve via la sola DT_NEEDED.
    LIBS += -L$$VLC_LIBDIR -lvlc -lvlccore -ldl

    vlclibs.files = $$files($$VLC_LIBDIR/libvlc.so*) $$files($$VLC_LIBDIR/libvlccore.so*)
    vlclibs.path = /usr/share/$${TARGET}/lib
    INSTALLS += vlclibs

    vlcplugins.files = $$VLC_LIBDIR/vlc
    vlcplugins.path = /usr/share/$${TARGET}/lib
    INSTALLS += vlcplugins

    # VLC license texts ship only when libvlc is actually bundled (GPLv2 +
    # LGPLv2.1, covering libvlc/libvlccore + the bundled plugins).
    vlclicenses.files = $$files($$PWD/licenses/vlc/*)
    vlclicenses.path = /usr/share/$${TARGET}/licenses/vlc
    INSTALLS += vlclicenses
} else {
    message(libvlc NOT vendored for $${TARGET_ARCHITECTURE} — building without Layer 3 (run scripts/build-libvlc.sh))
}

# ── droidmedia (Layer 1 — direct HW decode path, v0.3) ───────────────────────
# droidmedia (the lib gst-droid wraps) reaches the device's OMX decoders over
# the Android HAL via libhybris. Provided by droidmedia-devel in the SFOS target
# (system lib on-device); linked, not bundled. Gated on the package so the app
# still builds without it. v0.3.1 uses only the capability query (DroidCodec).
packagesExist(droidmedia) {
    message(droidmedia HW path enabled)
    DEFINES += HAVE_DROIDMEDIA
    # Use pkg-config flags directly (NOT CONFIG+=link_pkgconfig, which dropped the
    # sailfishapp linkage here). Evaluated in the SFOS build env where pkg-config
    # resolves droidmedia → -I/usr/include/droidmedia ... -ldroidmedia -ldl.
    QMAKE_CXXFLAGS += $$system(pkg-config --cflags droidmedia)
    LIBS += $$system(pkg-config --libs droidmedia)
    # Zero-copy video (v0.3.3): the decoder's gralloc buffers are wrapped in an
    # EGLImage and drawn as a GL_TEXTURE_EXTERNAL_OES scene-graph node, so we need
    # EGL + GLESv2 (the eglCreateImageKHR/glEGLImageTargetTexture2DOES extensions).
    QMAKE_CXXFLAGS += $$system(pkg-config --cflags egl glesv2)
    LIBS += $$system(pkg-config --libs egl glesv2)
    # Audio output (v0.3.3): decoded+resampled (libswresample, already linked with
    # ffmpeg) PCM is played via the PulseAudio simple API.
    QMAKE_CXXFLAGS += $$system(pkg-config --cflags libpulse-simple)
    LIBS += $$system(pkg-config --libs libpulse-simple)
    SOURCES += src/media/DroidCodec.cpp \
               src/media/DroidCodecBackend.cpp \
               src/media/DroidVideoSink.cpp
    HEADERS += src/media/DroidCodec.h \
               src/media/DroidCodecBackend.h \
               src/media/DroidVideoSink.h
} else {
    message(droidmedia NOT available — building without the direct HW path)
}
