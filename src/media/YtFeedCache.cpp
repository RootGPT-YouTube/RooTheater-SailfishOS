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

#include "YtFeedCache.h"

#include <QXmlStreamReader>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QStandardPaths>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonParseError>
#include <QSet>
#include <QDateTime>
#include <QRegularExpression>
#include <QLocale>

namespace {

// InnerTube renderers wrap the same video shape in a handful of names depending
// on the client; walk the whole answer and pick up every one of them.
void collect(const QJsonValue &v, const QString &key, QVector<QJsonObject> *out)
{
    if (v.isObject()) {
        const QJsonObject o = v.toObject();
        for (QJsonObject::const_iterator it = o.begin(); it != o.end(); ++it) {
            if (it.key() == key && it.value().isObject())
                out->append(it.value().toObject());
            else
                collect(it.value(), key, out);
        }
    } else if (v.isArray()) {
        const QJsonArray a = v.toArray();
        for (const QJsonValue &e : a)
            collect(e, key, out);
    }
}

// InnerTube text comes as {"simpleText":…}, {"runs":[{"text":…}]} or
// {"content":…} depending on the field and the client version.
QString textOf(const QJsonValue &v)
{
    const QJsonObject o = v.toObject();
    if (o.contains(QStringLiteral("simpleText")))
        return o.value(QStringLiteral("simpleText")).toString();
    if (o.contains(QStringLiteral("content")))
        return o.value(QStringLiteral("content")).toString();
    QString s;
    const QJsonArray runs = o.value(QStringLiteral("runs")).toArray();
    for (const QJsonValue &r : runs)
        s += r.toObject().value(QStringLiteral("text")).toString();
    return s;
}

}   // namespace

namespace YtFeedCache {

bool parseFeed(const QByteArray &xml, QVector<YtVideo> *out)
{
    // YouTube channel RSS is Atom: <feed><entry>… with yt:/media: extensions.
    QXmlStreamReader xr(xml);
    QVector<YtVideo> parsed;
    QString feedAuthor;
    bool sawFeed = false;       // did we get an Atom document at all?

    while (!xr.atEnd() && !xr.hasError()) {
        if (xr.readNext() != QXmlStreamReader::StartElement)
            continue;

        if (xr.name() == QLatin1String("feed")) {
            sawFeed = true;
        }

        if (xr.name() == QLatin1String("entry")) {
            YtVideo v;
            while (!(xr.isEndElement() && xr.name() == QLatin1String("entry"))) {
                if (xr.readNext() == QXmlStreamReader::StartElement) {
                    const QStringRef n = xr.name();
                    if (n == QLatin1String("videoId")) {
                        v.videoId = xr.readElementText();
                    } else if (n == QLatin1String("channelId")) {
                        v.channelId = xr.readElementText();
                    } else if (n == QLatin1String("title") && v.title.isEmpty()) {
                        v.title = xr.readElementText();
                    } else if (n == QLatin1String("published") && v.published == 0) {
                        const QDateTime dt = QDateTime::fromString(xr.readElementText(), Qt::ISODate);
                        if (dt.isValid())
                            v.published = dt.toMSecsSinceEpoch();
                    } else if (n == QLatin1String("thumbnail")) {
                        const QString u = xr.attributes().value(QLatin1String("url")).toString();
                        if (!u.isEmpty())
                            v.thumbnail = u;
                    } else if (n == QLatin1String("name") && v.channelName.isEmpty()) {
                        v.channelName = xr.readElementText();   // <author><name>
                    }
                }
                if (xr.atEnd())
                    break;
            }
            if (!v.videoId.isEmpty()) {
                if (v.thumbnail.isEmpty())
                    v.thumbnail = QStringLiteral("https://i.ytimg.com/vi/%1/mqdefault.jpg").arg(v.videoId);
                if (v.channelName.isEmpty())
                    v.channelName = feedAuthor;
                parsed.append(v);
            }
        } else if (xr.name() == QLatin1String("title") && feedAuthor.isEmpty()) {
            // The feed-level <title> is the channel name (fallback for entries).
            feedAuthor = xr.readElementText();
        }
    }

    // A real feed with no entries (a channel that has never uploaded) is a
    // success with nothing to add; anything that was not a feed is a failure.
    if (parsed.isEmpty())
        return sawFeed && !xr.hasError();

    *out = parsed;
    return true;
}

QString browseUrl()
{
    return QStringLiteral("https://www.youtube.com/youtubei/v1/browse?prettyPrint=false");
}

QByteArray browseBody(const QString &channelId)
{
    // The same keyless MWEB client the in-app search uses. `params` is the
    // opaque token for a channel's "Videos" tab — without it the answer is the
    // channel's home tab, which mixes in playlists and shorts.
    //
    // hl/gl come from the device: asking in English would get the titles
    // auto-translated for channels that publish translations, which is not what
    // the RSS used to show. The price is that the relative dates come localized
    // too — see relativeToEpoch().
    const QString locale = QLocale::system().name();          // e.g. "it_IT"
    const QString hl = locale.section(QLatin1Char('_'), 0, 0);
    const QString gl = locale.section(QLatin1Char('_'), 1, 1);
    QJsonObject client {
        { QStringLiteral("clientName"),    QStringLiteral("MWEB") },
        { QStringLiteral("clientVersion"), QStringLiteral("2.20250630.01.00") }
    };
    if (!hl.isEmpty()) client.insert(QStringLiteral("hl"), hl);
    if (!gl.isEmpty()) client.insert(QStringLiteral("gl"), gl);
    QJsonObject body {
        { QStringLiteral("context"), QJsonObject{ { QStringLiteral("client"), client } } },
        { QStringLiteral("browseId"), channelId },
        { QStringLiteral("params"), QStringLiteral("EgZ2aWRlb3PyBgQKAjoA") }
    };
    return QJsonDocument(body).toJson(QJsonDocument::Compact);
}

qint64 relativeToEpoch(const QString &text, qint64 nowMs)
{
    // "2 giorni fa", "2 days ago", "Trasmesso in streaming 3 settimane fa": take
    // the first number followed by a word and read that word as a unit. Only the
    // app's two languages are spelled out; an unrecognised one yields 0, which
    // sorts the video last and leaves its date blank rather than inventing one.
    static const QRegularExpression re(QStringLiteral("(\\d+)\\s*([^\\s\\d]+)"));
    QRegularExpressionMatchIterator it = re.globalMatch(text);
    while (it.hasNext()) {
        const QRegularExpressionMatch m = it.next();
        const qint64 n = m.captured(1).toLongLong();
        const QString u = m.captured(2).toLower();
        qint64 unit = 0;
        if (u.startsWith(QLatin1String("sec")))                                     unit = 1000LL;
        else if (u.startsWith(QLatin1String("min")))                                unit = 60LL * 1000;
        else if (u.startsWith(QLatin1String("hour")) || u.startsWith(QLatin1String("or")))    unit = 3600LL * 1000;
        else if (u.startsWith(QLatin1String("day"))  || u.startsWith(QLatin1String("giorn"))) unit = 86400LL * 1000;
        else if (u.startsWith(QLatin1String("week")) || u.startsWith(QLatin1String("settiman"))) unit = 7LL * 86400 * 1000;
        else if (u.startsWith(QLatin1String("month"))|| u.startsWith(QLatin1String("mes")))   unit = 30LL * 86400 * 1000;
        else if (u.startsWith(QLatin1String("year")) || u.startsWith(QLatin1String("ann")))   unit = 365LL * 86400 * 1000;
        if (unit > 0)
            return nowMs - n * unit;
    }
    return 0;
}

bool parseBrowse(const QByteArray &json, QVector<YtVideo> *out)
{
    const QJsonDocument doc = QJsonDocument::fromJson(json);
    if (!doc.isObject())
        return false;
    const QJsonObject root = doc.object();
    const QJsonObject meta = root.value(QStringLiteral("metadata")).toObject()
                                 .value(QStringLiteral("channelMetadataRenderer")).toObject();
    // No channel metadata ⇒ this was not a channel answer (an error page, a
    // consent wall, a changed client contract): a failure, not an empty channel.
    if (meta.isEmpty())
        return false;
    const QString channelName = meta.value(QStringLiteral("title")).toString();
    const QString channelId   = meta.value(QStringLiteral("externalId")).toString();

    QVector<QJsonObject> items;
    collect(root, QStringLiteral("videoWithContextRenderer"), &items);   // MWEB
    collect(root, QStringLiteral("videoRenderer"), &items);              // web
    collect(root, QStringLiteral("gridVideoRenderer"), &items);          // older grids

    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    QVector<YtVideo> parsed;
    QSet<QString> seen;
    for (const QJsonObject &o : items) {
        YtVideo v;
        v.videoId = o.value(QStringLiteral("videoId")).toString();
        if (v.videoId.isEmpty())
            v.videoId = o.value(QStringLiteral("navigationEndpoint")).toObject()
                         .value(QStringLiteral("watchEndpoint")).toObject()
                         .value(QStringLiteral("videoId")).toString();
        if (v.videoId.isEmpty() || seen.contains(v.videoId))
            continue;                       // a pinned video appears twice
        seen.insert(v.videoId);
        v.title = textOf(o.value(QStringLiteral("headline")));
        if (v.title.isEmpty())
            v.title = textOf(o.value(QStringLiteral("title")));
        v.published = relativeToEpoch(textOf(o.value(QStringLiteral("publishedTimeText"))), now);
        // Prefer the ~320px still: the same one the RSS pointed at, and the size
        // the list actually shows.
        const QJsonArray thumbs = o.value(QStringLiteral("thumbnail")).toObject()
                                   .value(QStringLiteral("thumbnails")).toArray();
        int best = -1;
        for (const QJsonValue &t : thumbs) {
            const QJsonObject to = t.toObject();
            const int w = to.value(QStringLiteral("width")).toInt();
            if (v.thumbnail.isEmpty() || qAbs(w - 320) < qAbs(best - 320)) {
                v.thumbnail = to.value(QStringLiteral("url")).toString();
                best = w;
            }
        }
        if (v.thumbnail.isEmpty())
            v.thumbnail = QStringLiteral("https://i.ytimg.com/vi/%1/mqdefault.jpg").arg(v.videoId);
        v.channelId   = channelId;
        v.channelName = channelName;
        parsed.append(v);
    }

    if (parsed.isEmpty())
        return true;        // a real channel with nothing in its Videos tab
    *out = parsed;
    return true;
}

QString path(const QString &channelId)
{
    // Same sandbox rule as the subscriptions file (YtSubscriptions::storePath):
    // Sailjail grants write access under the app's IDENTITY dir, so the cache
    // must live in ~/.cache/com.github.RootGPT_YouTube/rootheater/ and NOT in
    // ~/.cache/harbour-rootheater/, which is what QStandardPaths::AppCacheLocation
    // returns here (applicationName is "harbour-rootheater", organization unset).
    // Writing to the unpermitted path fails SILENTLY — that is how the
    // subscriptions once vanished on restart.
    QString id;                        // a channel id must never become a path
    for (const QChar &c : channelId)
        if (c.isLetterOrNumber() || c == QLatin1Char('_') || c == QLatin1Char('-'))
            id += c;
    if (id.isEmpty())
        return QString();
    const QString base = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation);
    return base + QStringLiteral("/com.github.RootGPT_YouTube/rootheater/feeds/")
         + id + QStringLiteral(".json");
}

void write(const QString &channelId, const QVector<YtVideo> &vids)
{
    // Only a non-empty list: a channel that legitimately has no uploads parses
    // fine and would otherwise wipe a perfectly good cache with nothing.
    if (vids.isEmpty())
        return;
    const QString file = path(channelId);
    if (file.isEmpty())
        return;
    QDir().mkpath(QFileInfo(file).absolutePath());

    QJsonArray arr;
    for (const YtVideo &v : vids) {
        QJsonObject o;
        o[QStringLiteral("videoId")]     = v.videoId;
        o[QStringLiteral("title")]       = v.title;
        o[QStringLiteral("thumbnail")]   = v.thumbnail;
        o[QStringLiteral("channelId")]   = v.channelId;
        o[QStringLiteral("channelName")] = v.channelName;
        // qint64 through QJsonValue is a double: video ids and ms timestamps are
        // both well inside the 2^53 that survives that round trip exactly.
        o[QStringLiteral("published")]   = static_cast<double>(v.published);
        arr.append(o);
    }
    QJsonObject root;
    root[QStringLiteral("saved")]  = static_cast<double>(QDateTime::currentMSecsSinceEpoch());
    root[QStringLiteral("videos")] = arr;

    // QSaveFile so a crash mid-write cannot leave a truncated cache behind: the
    // old file stays until the new one is complete.
    QSaveFile f(file);
    if (!f.open(QIODevice::WriteOnly)) {
        qWarning("YtFeedCache: cannot write cache %s", qPrintable(file));
        return;
    }
    f.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
    if (!f.commit())
        qWarning("YtFeedCache: cache commit failed for %s", qPrintable(file));
}

QVector<YtVideo> read(const QString &channelId, qint64 *savedAt)
{
    QVector<YtVideo> out;
    if (savedAt)
        *savedAt = 0;
    const QString file = path(channelId);
    if (file.isEmpty())
        return out;

    QFile f(file);
    if (!f.open(QIODevice::ReadOnly)) {
        // Not an error in itself (a channel never loaded yet has no cache), but
        // the path is worth having in the journal: it is the one thing that can
        // silently differ between what we write and what the sandbox permits.
        qWarning("YtFeedCache: no cache for %s at %s — %s", qPrintable(channelId),
                 qPrintable(file), qPrintable(f.errorString()));
        return out;
    }
    const QByteArray raw = f.readAll();
    QJsonParseError perr;
    const QJsonDocument doc = QJsonDocument::fromJson(raw, &perr);
    if (!doc.isObject()) {
        qWarning("YtFeedCache: cache %s unreadable (%d bytes) — %s", qPrintable(file),
                 raw.size(), qPrintable(perr.errorString()));
        return out;
    }
    const QJsonObject root = doc.object();
    if (savedAt)
        *savedAt = static_cast<qint64>(root.value(QStringLiteral("saved")).toDouble());

    const QJsonArray arr = root.value(QStringLiteral("videos")).toArray();
    for (const QJsonValue &val : arr) {
        const QJsonObject o = val.toObject();
        YtVideo v;
        v.videoId     = o.value(QStringLiteral("videoId")).toString();
        if (v.videoId.isEmpty())
            continue;
        v.title       = o.value(QStringLiteral("title")).toString();
        v.thumbnail   = o.value(QStringLiteral("thumbnail")).toString();
        v.channelId   = o.value(QStringLiteral("channelId")).toString();
        v.channelName = o.value(QStringLiteral("channelName")).toString();
        v.published   = static_cast<qint64>(o.value(QStringLiteral("published")).toDouble());
        if (v.thumbnail.isEmpty())
            v.thumbnail = QStringLiteral("https://i.ytimg.com/vi/%1/mqdefault.jpg").arg(v.videoId);
        out.append(v);
    }
    if (out.isEmpty())
        qWarning("YtFeedCache: cache %s has no usable entries (%d bytes, %d raw)",
                 qPrintable(file), raw.size(), arr.size());
    return out;
}

}   // namespace YtFeedCache
