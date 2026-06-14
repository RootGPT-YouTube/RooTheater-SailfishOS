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
RT_APP_VERSION = 0.1.0
VERSION = $$RT_APP_VERSION

CONFIG += sailfishapp sailfishapp_i18n c++17

# v0.1 baseline engine: QtMultimedia (MediaPlayer + VideoOutput). On SFOS this
# routes through gst-droid → hardware-accelerated decode for common formats.
# Layer 2/3 (libvlc) and the custom droidmedia HW path land in later versions.
QT += core multimedia

DEFINES += APP_VERSION=\\\"$$RT_APP_VERSION\\\"

SOURCES += src/harbour-rootheater.cpp

# License compliance: the GPLv3 text (and, as bundled libs land, their
# LGPL/GPL/BSD texts) must reach whoever receives the RPM. AboutPage points
# users to /usr/share/harbour-rootheater/licenses/.
licenses.files = $$PWD/LICENSE
licenses.path = /usr/share/$${TARGET}/licenses
INSTALLS += licenses

DISTFILES += LICENSE \
    qml/harbour-rootheater.qml \
    qml/cover/CoverPage.qml \
    qml/pages/MainPage.qml \
    qml/pages/PlayerPage.qml \
    qml/pages/AboutPage.qml \
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
