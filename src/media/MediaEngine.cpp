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

#include "MediaEngine.h"
#include "CoverImageProvider.h"

#include <QtConcurrent/QtConcurrentRun>
#include <QImage>
#include <QLocale>
#include <QHash>

#ifdef HAVE_DROIDMEDIA
#include "DroidCodec.h"
#endif

MediaEngine::MediaEngine(QObject *parent)
    : QObject(parent)
{
    connect(&m_watcher, &QFutureWatcher<MediaProbe::Result>::finished,
            this, &MediaEngine::onProbeFinished);
}

void MediaEngine::probe(const QString &url)
{
    if (m_probing)
        return; // one probe at a time; ignore re-entrant calls

    m_probing = true;
    emit probingChanged();

    // ffmpeg open/find_stream_info blocks (network sources especially), so run
    // it on the global thread pool and collect the result via the watcher.
    m_watcher.setFuture(QtConcurrent::run(&MediaProbe::probe, url));
}

void MediaEngine::onProbeFinished()
{
    m_result = m_watcher.result();
    m_backend = chooseBackend(m_result);

    // Decode the embedded cover art (if any) into the shared image provider and
    // expose a cache-busting URL for QML; empty when the file has no cover.
    m_hasCover = false;
    m_coverSource.clear();
    if (!m_result.coverArt.isEmpty() && g_coverProvider) {
        QImage cover;
        if (cover.loadFromData(m_result.coverArt) && !cover.isNull()) {
            g_coverProvider->setImage(cover);
            m_coverSource = QStringLiteral("image://rtcover/%1").arg(++m_coverToken);
            m_hasCover = true;
        }
    }

    m_probing = false;
    emit probingChanged();
    emit probed();
}

MediaEngine::Backend MediaEngine::chooseBackend(const MediaProbe::Result &r)
{
    // Probe failed (unreadable/exotic container or protocol ffmpeg couldn't
    // open): hand it to libvlc, our broad-coverage backend.
    if (!r.ok)
        return Libvlc;

    // Audio-only: the QtMultimedia/gst-droid baseline plays it fine.
    if (!r.hasVideo)
        return QtMultimedia;

    const QString c = r.videoCodec;

#ifdef HAVE_DROIDMEDIA
    // Capability-driven (v0.3): take the direct HW path only if the device's
    // droidmedia actually exposes a decoder for this codec/size.
    if (DroidCodec::decoderSupported(c, r.width, r.height))
        return Droidmedia;
#else
    // No droidmedia at build time: still label the guaranteed HW codecs as
    // Droidmedia (they play via the QtMultimedia/gst-droid baseline for now).
    if (c == QLatin1String("h264") || c == QLatin1String("hevc") || c == QLatin1String("vp9"))
        return Droidmedia;
#endif

    // Common codecs gst-droid usually handles (HW opportunistically, else SW):
    // keep them on the QtMultimedia baseline.
    if (c == QLatin1String("h264") || c == QLatin1String("hevc") || c == QLatin1String("vp9")
        || c == QLatin1String("mpeg2video") || c == QLatin1String("mpeg4")
        || c == QLatin1String("vp8"))
        return QtMultimedia;

    // Anything else with video is "exotic" → libvlc coverage.
    return Libvlc;
}

QString MediaEngine::recommendedBackendName() const
{
    switch (m_backend) {
    case Droidmedia:   return QStringLiteral("droidmedia (HW)");
    case QtMultimedia: return QStringLiteral("QtMultimedia");
    case Libvlc:       return QStringLiteral("libVLC");
    case Software:     return QStringLiteral("software");
    case Auto:
    default:           return QStringLiteral("auto");
    }
}

QVariantList MediaEngine::tracks() const
{
    QVariantList out;
    int order[3] = {0, 0, 0};
    for (const MediaProbe::Result::Track &t : m_result.tracks) {
        QVariantMap m;
        m.insert(QStringLiteral("index"), t.index);
        m.insert(QStringLiteral("type"), t.type == MediaProbe::Result::VideoTrack ? QStringLiteral("video")
                                       : t.type == MediaProbe::Result::AudioTrack ? QStringLiteral("audio")
                                                                                  : QStringLiteral("subtitle"));
        m.insert(QStringLiteral("order"), order[t.type]++);
        m.insert(QStringLiteral("codec"), t.codec);
        m.insert(QStringLiteral("language"), t.language.isEmpty() ? QString() : languageName(t.language));
        m.insert(QStringLiteral("title"), t.title);
        m.insert(QStringLiteral("isDefault"), t.isDefault);
        m.insert(QStringLiteral("forced"), t.forced);
        m.insert(QStringLiteral("textual"), t.textual);
        m.insert(QStringLiteral("width"), t.width);
        m.insert(QStringLiteral("height"), t.height);
        m.insert(QStringLiteral("channels"), t.channels);
        out.append(m);
    }
    return out;
}

QString MediaEngine::languageName(const QString &code)
{
    // Containers tag tracks with ISO 639-2 (mostly the bibliographic "B" codes:
    // ger, fre, chi...), which QLocale doesn't take; map the common ones to 639-1.
    static const QHash<QString, QString> iso6392 = {
        {"ita", "it"}, {"eng", "en"}, {"fre", "fr"}, {"fra", "fr"}, {"ger", "de"},
        {"deu", "de"}, {"spa", "es"}, {"por", "pt"}, {"dut", "nl"}, {"nld", "nl"},
        {"rus", "ru"}, {"pol", "pl"}, {"cze", "cs"}, {"ces", "cs"}, {"slo", "sk"},
        {"slk", "sk"}, {"hun", "hu"}, {"rum", "ro"}, {"ron", "ro"}, {"gre", "el"},
        {"ell", "el"}, {"tur", "tr"}, {"ara", "ar"}, {"heb", "he"}, {"hin", "hi"},
        {"jpn", "ja"}, {"kor", "ko"}, {"chi", "zh"}, {"zho", "zh"}, {"swe", "sv"},
        {"nor", "nb"}, {"nob", "nb"}, {"dan", "da"}, {"fin", "fi"}, {"est", "et"},
        {"ukr", "uk"}, {"bul", "bg"}, {"hrv", "hr"}, {"srp", "sr"}, {"slv", "sl"},
        {"cat", "ca"}, {"lat", "la"}, {"tha", "th"}, {"vie", "vi"}, {"ind", "id"},
        {"may", "ms"}, {"msa", "ms"}, {"per", "fa"}, {"fas", "fa"}, {"lit", "lt"},
        {"lav", "lv"}, {"ice", "is"}, {"isl", "is"}, {"glg", "gl"}, {"baq", "eu"},
        {"eus", "eu"},
    };
    const QString c = code.trimmed().toLower();
    const QString two = c.length() == 3 ? iso6392.value(c) : c;
    if (two.length() == 2) {
        const QLocale loc(two);
        if (loc.language() != QLocale::C) {
            const QString n = QLocale().languageToString(loc.language());
            // languageToString is English; prefer the language's own name, which
            // reads right in any UI ("italiano", "English", "Deutsch").
            // ("en" alone resolves to en_US, whose native name is "American English")
            const QString native = two == QLatin1String("en") ? QStringLiteral("English")
                                                              : loc.nativeLanguageName();
            return native.isEmpty() ? n : native;
        }
    }
    return code;
}
