/*
    RooTheater — a multimedia player for Sailfish OS.
    Copyright (C) 2026 RootGPT

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program. If not, see <http://www.gnu.org/licenses/>.
*/

#include "VlcBackend.h"

#include <QUrl>
#include <QFile>

#include <cstring>
#include <cstdarg>
#include <cstdio>
#include <dlfcn.h>

#include <vlc/vlc.h>

namespace {
// Where the bundled VLC plugins land in the RPM (see the .pro). libvlc must be
// told this before libvlc_new(), otherwise it scans the build-host default and
// finds nothing on-device.
const char *kBundledPluginPath = "/usr/share/harbour-rootheater/lib/vlc/plugins";

// libvlc → journald bridge (the invoker captures stderr). Errors only: the path
// is CPU/vmem and emits frequent A/V-timing warnings we don't want to log.
void vlcLogCb(void *, int level, const libvlc_log_t *, const char *fmt, va_list args)
{
    if (level < LIBVLC_ERROR)
        return;
    char buf[512];
    vsnprintf(buf, sizeof(buf), fmt, args);
    fprintf(stderr, "[RT-VLC] %s\n", buf);
    fflush(stderr);
}
}

VlcBackend::VlcBackend(QObject *parent)
    : QObject(parent)
{
    if (qEnvironmentVariableIsEmpty("VLC_PLUGIN_PATH")
        && QFile::exists(QString::fromLatin1(kBundledPluginPath))) {
        qputenv("VLC_PLUGIN_PATH", kBundledPluginPath);
    }

    // The bundled pulse audio-output plugin links libvlc_pulse.so.0 (in lib/vlc/),
    // which isn't on the loader path and which the plugin carries no RPATH for.
    // Preload it RTLD_GLOBAL so the plugin's dependency is already satisfied when
    // libvlc dlopen's it — otherwise libvlc reports "no suitable audio output
    // module" and plays silently.
    dlopen("/usr/share/harbour-rootheater/lib/vlc/libvlc_pulse.so.0", RTLD_NOW | RTLD_GLOBAL);

    // Lean libvlc instance: no X, no on-screen title; audio forced to the bundled
    // PulseAudio output. Video is delivered through the vmem callbacks per media.
    const char *args[] = {
        "--no-xlib",
        "--no-video-title-show",
        "--intf", "dummy",
        "--aout=pulse",
    };
    m_vlc = libvlc_new(sizeof(args) / sizeof(args[0]), args);
    if (m_vlc) {
        libvlc_log_set(m_vlc, &vlcLogCb, this);
        m_player = libvlc_media_player_new(m_vlc);
    }

    m_pollTimer.setInterval(250);
    connect(&m_pollTimer, &QTimer::timeout, this, &VlcBackend::poll);
}

VlcBackend::~VlcBackend()
{
    if (m_player) {
        libvlc_media_player_stop(m_player);
        libvlc_media_player_release(m_player);
    }
    if (m_vlc)
        libvlc_release(m_vlc);
}

void VlcBackend::setVideoOutput(VideoSurface *output)
{
    if (m_output == output)
        return;
    if (m_output)
        disconnect(this, &VlcBackend::frameReady, m_output, &VideoSurface::presentFrame);
    m_output = output;
    if (m_output) {
        // Queued: displayCb runs on libvlc's video thread, the surface paints on
        // the GUI thread. The QImage carried is already a detached copy.
        connect(this, &VlcBackend::frameReady,
                m_output, &VideoSurface::presentFrame, Qt::QueuedConnection);
    }
    emit videoOutputChanged();
}

void VlcBackend::play(const QString &url)
{
    if (!m_player)
        return;

    libvlc_media_t *media = nullptr;
    const QString scheme = QUrl(url).scheme();
    const bool isNetwork = !scheme.isEmpty() && scheme != QLatin1String("file");
    if (isNetwork)
        media = libvlc_media_new_location(m_vlc, url.toUtf8().constData());
    else
        media = libvlc_media_new_path(m_vlc, QUrl(url).isLocalFile()
                                      ? QUrl(url).toLocalFile().toUtf8().constData()
                                      : url.toUtf8().constData());
    if (!media)
        return;

    libvlc_media_player_set_media(m_player, media);
    libvlc_media_release(media);

    // Route decoded video into our CPU buffer. Format callbacks let libvlc tell
    // us the real picture size so we size the buffer to the stream.
    libvlc_video_set_callbacks(m_player, &VlcBackend::lockCb, &VlcBackend::unlockCb,
                               &VlcBackend::displayCb, this);
    libvlc_video_set_format_callbacks(m_player, &VlcBackend::setupCb, &VlcBackend::cleanupCb);

    setState(Opening);
    libvlc_media_player_play(m_player);
    libvlc_audio_set_mute(m_player, 0); // ensure not muted; volume left to the system
    m_pollTimer.start();
}

void VlcBackend::play()
{
    if (m_player) {
        libvlc_media_player_set_pause(m_player, 0);
        m_pollTimer.start();
    }
}

void VlcBackend::pause()
{
    if (m_player)
        libvlc_media_player_set_pause(m_player, 1);
}

void VlcBackend::togglePause()
{
    if (m_player)
        libvlc_media_player_pause(m_player); // toggles play/pause
}

void VlcBackend::stop()
{
    if (!m_player)
        return;
    libvlc_media_player_stop(m_player);
    m_pollTimer.stop();
    setState(Stopped);
    if (m_output)
        m_output->clear();
}

void VlcBackend::seek(qlonglong ms)
{
    if (m_player && libvlc_media_player_is_seekable(m_player))
        libvlc_media_player_set_time(m_player, static_cast<libvlc_time_t>(ms));
}

void VlcBackend::poll()
{
    if (!m_player)
        return;

    const qlonglong pos = libvlc_media_player_get_time(m_player);
    if (pos != m_position) {
        m_position = pos;
        emit positionChanged();
    }
    const qlonglong len = libvlc_media_player_get_length(m_player);
    if (len != m_duration) {
        m_duration = len;
        emit durationChanged();
    }
    const bool seek = libvlc_media_player_is_seekable(m_player) != 0;
    if (seek != m_seekable) {
        m_seekable = seek;
        emit seekableChanged();
    }

    switch (libvlc_media_player_get_state(m_player)) {
    case libvlc_Opening:    setState(Opening); break;
    case libvlc_Buffering:  setState(Buffering); break;
    case libvlc_Playing:    setState(Playing); break;
    case libvlc_Paused:     setState(Paused); break;
    case libvlc_Ended:      setState(Ended); m_pollTimer.stop(); break;
    case libvlc_Error:      setState(Error); m_pollTimer.stop(); break;
    case libvlc_Stopped:
    case libvlc_NothingSpecial:
    default:                setState(Stopped); break;
    }
}

void VlcBackend::setState(State s)
{
    if (m_state == s)
        return;
    m_state = s;
    emit stateChanged();
}

// ── vmem callbacks (libvlc video thread) ─────────────────────────────────────

unsigned VlcBackend::setupCb(void **opaque, char *chroma, unsigned *width,
                             unsigned *height, unsigned *pitches, unsigned *lines)
{
    auto *self = static_cast<VlcBackend *>(*opaque);

    // RV32: 32-bit RGB, one plane. Matches QImage::Format_RGB32 on little-endian.
    std::memcpy(chroma, "RV32", 4);
    self->m_width = *width;
    self->m_height = *height;
    self->m_pitch = *width * 4;
    pitches[0] = self->m_pitch;
    lines[0] = *height;

    self->m_buffer.assign(static_cast<size_t>(self->m_pitch) * *height, 0);
    return 1; // one buffer
}

void VlcBackend::cleanupCb(void *opaque)
{
    auto *self = static_cast<VlcBackend *>(opaque);
    self->m_buffer.clear();
    self->m_buffer.shrink_to_fit();
}

void *VlcBackend::lockCb(void *opaque, void **planes)
{
    auto *self = static_cast<VlcBackend *>(opaque);
    planes[0] = self->m_buffer.data();
    return nullptr; // picture id (unused, single buffer)
}

void VlcBackend::unlockCb(void *opaque, void *picture, void *const *planes)
{
    Q_UNUSED(opaque)
    Q_UNUSED(picture)
    Q_UNUSED(planes)
}

void VlcBackend::displayCb(void *opaque, void *picture)
{
    Q_UNUSED(picture)
    auto *self = static_cast<VlcBackend *>(opaque);
    if (self->m_buffer.empty() || self->m_width == 0 || self->m_height == 0)
        return;

    // Wrap the buffer, then copy() to detach before it crosses threads (the
    // decoder reuses the same buffer for the next frame).
    QImage frame(self->m_buffer.data(), self->m_width, self->m_height,
                 self->m_pitch, QImage::Format_RGB32);
    emit self->frameReady(frame.copy());
}
