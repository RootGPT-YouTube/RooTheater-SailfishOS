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

#ifndef MEDIAPROBE_H
#define MEDIAPROBE_H

#include <QString>
#include <QByteArray>
#include <QVariantMap>

// MediaProbe wraps libavformat/libavcodec to inspect a media source (local file
// or network URL) without playing it: it demuxes the container, reads the
// stream list and reports the container/codecs/resolution/duration. This is the
// foundation of the engine facade — the probe result feeds the capability-driven
// backend selection (see MediaEngine) and, later, the droidmedia HW path which
// needs the elementary-stream codec to decide HW vs SW.
//
// Pure C++ (only QString), no Qt object/event-loop dependency, so it stays
// unit-testable and reusable behind the QML-facing MediaEngine.
class MediaProbe
{
public:
    struct Result {
        bool ok = false;            // probe succeeded (container opened + parsed)
        QString error;              // human-readable reason when !ok

        QString url;                // the source that was probed
        bool isNetwork = false;     // URL has a non-file scheme (http/rtsp/...)
        QString container;          // demuxer/format long name (e.g. "QuickTime / MOV")
        QString formatName;         // demuxer short name (e.g. "mov,mp4,m4a,...")
        qint64 durationMs = -1;     // total duration in ms, -1 if unknown

        bool hasVideo = false;
        QString videoCodec;         // e.g. "h264", "hevc", "vp9" (avcodec short name)
        int width = 0;
        int height = 0;
        int rotation = 0;           // display rotation, clockwise degrees (0/90/180/270)

        bool hasAudio = false;
        QString audioCodec;         // e.g. "aac", "opus"

        QByteArray coverArt;        // embedded cover image bytes (JPEG/PNG), empty if none
    };

    // Open and inspect `url`. Network probing requires the network protocols to
    // be compiled into ffmpeg (they are, see scripts/build-ffmpeg.sh). Blocking
    // call: callers on the GUI thread should keep sources local/fast or move it
    // off-thread (MediaEngine handles threading policy).
    static Result probe(const QString &url);

    // Standalone, lazy cover-art read for a single file: opens the container and
    // returns the first "attached picture" (album art) bytes, empty if none. Used
    // by the path-keyed TrackCoverProvider to decode covers on demand for the
    // gallery grids without a full probe. Blocking — callers run it off-thread
    // (the image provider forces asynchronous loading).
    static QByteArray coverArt(const QString &url);

    // Container/stream metadata tags (title, artist, album, …) as a flat map with
    // lower-cased keys. Format-level tags win; audio-stream tags fill any gaps.
    // Blocking, like probe()/coverArt() — callers run it off-thread (TagReader).
    static QVariantMap metadata(const QString &url);

private:
    MediaProbe() = delete;
};

#endif // MEDIAPROBE_H
