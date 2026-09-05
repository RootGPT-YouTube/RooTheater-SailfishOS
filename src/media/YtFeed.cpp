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

#include "YtFeed.h"

#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QUrl>
#include <QXmlStreamReader>
#include <QTimer>
#include <QDir>
#include <QFileInfo>
#include <QSaveFile>
#include <QFile>
#include <QStandardPaths>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonParseError>
#include <QDateTime>
#include <algorithm>

YtFeed::YtFeed(QObject *parent)
    : QAbstractListModel(parent)
    , m_nam(new QNetworkAccessManager(this))
{
    // Qt 5.6's ConnMan bearer plugin sometimes decides the device is offline when
    // it is not (an untranslatable technology in the service list is enough), and
    // QNetworkAccessManager then refuses every request with NetworkSessionFailed
    // without a single packet leaving. Nothing on the app side recovers from that,
    // not even a restart. Take the decision away from the bearer plugin: a request
    // on a genuinely dead network fails on its own, with a real error.
    m_nam->setNetworkAccessible(QNetworkAccessManager::Accessible);
}

YtFeed::~YtFeed() = default;

int YtFeed::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_videos.size();
}

QVariant YtFeed::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_videos.size())
        return QVariant();
    const Video &v = m_videos.at(index.row());
    switch (role) {
    case VideoIdRole:     return v.videoId;
    case TitleRole:       return v.title;
    case ThumbnailRole:   return v.thumbnail;
    case ChannelIdRole:   return v.channelId;
    case ChannelNameRole: return v.channelName;
    case PublishedRole:   return v.published;
    case WatchUrlRole:    return QStringLiteral("https://www.youtube.com/watch?v=") + v.videoId;
    default:              return QVariant();
    }
}

QHash<int, QByteArray> YtFeed::roleNames() const
{
    return {
        { VideoIdRole,     "videoId" },
        { TitleRole,       "title" },
        { ThumbnailRole,   "thumbnail" },
        { ChannelIdRole,   "channelId" },
        { ChannelNameRole, "channelName" },
        { PublishedRole,   "published" },
        { WatchUrlRole,    "watchUrl" }
    };
}

void YtFeed::loadChannels(const QStringList &channelIds)
{
    // New load: invalidate any in-flight replies and clear.
    ++m_generation;
    const int gen = m_generation;

    beginResetModel();
    m_videos.clear();
    endResetModel();
    emit countChanged();

    m_pending = 0;
    m_retries.clear();
    m_failed = 0;
    m_lastError.clear();
    m_stale = 0;
    m_staleSince = 0;
    emit errorChanged();
    QStringList ids;
    for (const QString &id : channelIds)
        if (!id.isEmpty())
            ids << id;
    if (ids.isEmpty()) {
        emit loadingChanged();  // ensure QML sees loading==false
        return;
    }

    m_pending = ids.size();
    m_idQueue = ids;
    m_active = 0;
    emit loadingChanged();
    startNext(gen);
}

void YtFeed::startNext(int gen)
{
    // Cap concurrent RSS fetches: firing dozens of parallel TLS requests at once
    // spikes memory/fds and can crash the app on a constrained device.
    const int kMax = 6;
    // A stalled mobile connection can hang forever; a transient error (TLS reset,
    // DNS blip, YouTube rate-limit) would otherwise drop a channel silently. Guard
    // both with a per-request timeout and a couple of re-queued retries so "reload"
    // (and the initial load) actually recover instead of showing partial results.
    const int kTimeoutMs  = 12000;
    const int kRetryMax   = 2;
    const int kRetryDelay = 1000;

    while (m_active < kMax && !m_idQueue.isEmpty()) {
        const QString id = m_idQueue.takeFirst();
        ++m_active;
        QUrl url(QStringLiteral("https://www.youtube.com/feeds/videos.xml?channel_id=") + id);
        QNetworkRequest req(url);
        req.setAttribute(QNetworkRequest::FollowRedirectsAttribute, true);
        // A benign UA reduces the chance of being bot-filtered / rate-limited.
        req.setHeader(QNetworkRequest::UserAgentHeader,
                      QStringLiteral("Mozilla/5.0 (RooTheater)"));
        QNetworkReply *reply = m_nam->get(req);

        // Qt 5.6 has no QNetworkRequest::setTransferTimeout, so bound the request
        // with a single-shot timer that aborts a stalled reply (→ finished w/ error).
        QTimer *timer = new QTimer(reply);
        timer->setSingleShot(true);
        connect(timer, &QTimer::timeout, reply, &QNetworkReply::abort);
        timer->start(kTimeoutMs);

        connect(reply, &QNetworkReply::finished, this,
                [this, reply, timer, id, gen, kRetryMax, kRetryDelay]() {
            timer->stop();
            reply->deleteLater();
            if (gen != m_generation)
                return;         // superseded — leave the newer load's counters alone
            --m_active;

            const int http = reply->attribute(
                        QNetworkRequest::HttpStatusCodeAttribute).toInt();
            const QByteArray body = reply->error() == QNetworkReply::NoError
                                  ? reply->readAll() : QByteArray();
            QString reason;
            QVector<Video> parsed;

            if (reply->error() != QNetworkReply::NoError) {
                reason = http > 0
                       ? tr("HTTP %1 — %2").arg(http).arg(reply->errorString())
                       : reply->errorString();
            } else if (!parseFeed(body, &parsed)) {
                // HTTP 200 with a body that is not an Atom feed. YouTube answers
                // this way when it serves a consent/error/bot-check page instead of
                // the feed, and treating it as success is exactly what made a failed
                // channel look like an empty one. Retry it like any other failure.
                reason = tr("invalid response (HTTP %1, %2 bytes)")
                         .arg(http).arg(body.size());
            }

            if (reason.isEmpty()) {
                appendVideos(parsed);
                // Keep the last good list for this channel. Only a non-empty one:
                // a channel that legitimately has no uploads parses fine and would
                // otherwise wipe a perfectly good cache with nothing.
                if (!parsed.isEmpty())
                    writeCache(id, parsed);
                finishOne();
            } else if (m_retries.value(id) < kRetryMax) {
                // Transient failure: re-queue this channel after a short backoff
                // instead of counting it done and losing it.
                m_retries[id] += 1;
                qWarning("YtFeed: channel %s failed (%s) — retry %d/%d",
                         qPrintable(id), qPrintable(reason),
                         m_retries.value(id), kRetryMax);
                QTimer::singleShot(kRetryDelay * m_retries.value(id), this,
                                   [this, id, gen]() {
                    if (gen != m_generation)
                        return;
                    m_idQueue << id;
                    startNext(gen);
                });
            } else {
                failOne(id, reason);   // give up on this channel after the retries
            }
            startNext(gen);     // fill the freed slot with the next queued channel
        });
    }
}

bool YtFeed::parseFeed(const QByteArray &xml, QVector<Video> *out) const
{
    // YouTube channel RSS is Atom: <feed><entry>… with yt:/media: extensions.
    QXmlStreamReader xr(xml);
    QVector<Video> parsed;
    QString feedAuthor;
    bool sawFeed = false;       // did we get an Atom document at all?

    while (!xr.atEnd() && !xr.hasError()) {
        if (xr.readNext() != QXmlStreamReader::StartElement)
            continue;

        if (xr.name() == QLatin1String("feed")) {
            sawFeed = true;
        }

        if (xr.name() == QLatin1String("entry")) {
            Video v;
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

void YtFeed::appendVideos(const QVector<Video> &vids)
{
    if (vids.isEmpty())
        return;
    beginInsertRows(QModelIndex(), m_videos.size(), m_videos.size() + vids.size() - 1);
    m_videos += vids;
    endInsertRows();
}

void YtFeed::failOne(const QString &channelId, const QString &reason)
{
    ++m_failed;
    m_lastError = reason;
    qWarning("YtFeed: channel %s GIVEN UP after retries — %s",
             qPrintable(channelId), qPrintable(reason));

    // The feed service can be down while YouTube itself is fine: measured on
    // 2026-09-05, feeds/videos.xml answered 404 (and sometimes 500) for EVERY
    // channel — including YouTube's own — while /channel/UC… still answered 200.
    // The videos that feed would have listed stay watchable throughout, because
    // playback goes to the watch page and only needs the video id. So rather
    // than show an empty page, fall back to the last list saved for this
    // channel: out of date, said so in the UI, and still usable.
    qint64 savedAt = 0;
    const QVector<Video> cached = readCache(channelId, &savedAt);
    if (!cached.isEmpty()) {
        appendVideos(cached);
        ++m_stale;
        if (m_staleSince == 0 || (savedAt > 0 && savedAt < m_staleSince))
            m_staleSince = savedAt;
        qWarning("YtFeed: channel %s served from cache — %d video(s), saved %s",
                 qPrintable(channelId), cached.size(),
                 qPrintable(QDateTime::fromMSecsSinceEpoch(savedAt).toString(Qt::ISODate)));
    }

    emit errorChanged();
    finishOne();
}

QString YtFeed::cachePath(const QString &channelId)
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

void YtFeed::writeCache(const QString &channelId, const QVector<Video> &vids) const
{
    const QString path = cachePath(channelId);
    if (path.isEmpty())
        return;
    QDir().mkpath(QFileInfo(path).absolutePath());

    QJsonArray arr;
    for (const Video &v : vids) {
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
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly)) {
        qWarning("YtFeed: cannot write cache %s", qPrintable(path));
        return;
    }
    f.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
    if (!f.commit())
        qWarning("YtFeed: cache commit failed for %s", qPrintable(path));
}

QVector<YtFeed::Video> YtFeed::readCache(const QString &channelId, qint64 *savedAt) const
{
    QVector<Video> out;
    if (savedAt)
        *savedAt = 0;
    const QString path = cachePath(channelId);
    if (path.isEmpty())
        return out;

    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        // Not an error in itself (a channel never loaded yet has no cache), but
        // the path is worth having in the journal: it is the one thing that can
        // silently differ between what we write and what the sandbox permits.
        qWarning("YtFeed: no cache for %s at %s — %s", qPrintable(channelId),
                 qPrintable(path), qPrintable(f.errorString()));
        return out;
    }
    const QByteArray raw = f.readAll();
    QJsonParseError perr;
    const QJsonDocument doc = QJsonDocument::fromJson(raw, &perr);
    if (!doc.isObject()) {
        qWarning("YtFeed: cache %s unreadable (%d bytes) — %s", qPrintable(path),
                 raw.size(), qPrintable(perr.errorString()));
        return out;
    }
    const QJsonObject root = doc.object();
    if (savedAt)
        *savedAt = static_cast<qint64>(root.value(QStringLiteral("saved")).toDouble());

    const QJsonArray arr = root.value(QStringLiteral("videos")).toArray();
    for (const QJsonValue &val : arr) {
        const QJsonObject o = val.toObject();
        Video v;
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
        qWarning("YtFeed: cache %s has no usable entries (%d bytes, %d raw)",
                 qPrintable(path), raw.size(), arr.size());
    return out;
}

void YtFeed::finishOne()
{
    if (m_pending > 0)
        --m_pending;
    if (m_pending == 0) {
        // All feeds in: sort newest-first and refresh the view in one shot.
        std::stable_sort(m_videos.begin(), m_videos.end(),
                         [](const Video &a, const Video &b) { return a.published > b.published; });
        beginResetModel();
        endResetModel();
        emit countChanged();
        emit loadingChanged();
        if (m_failed > 0)
            qWarning("YtFeed: load finished with %d video(s), %d channel(s) failed",
                     m_videos.size(), m_failed);
    }
}
