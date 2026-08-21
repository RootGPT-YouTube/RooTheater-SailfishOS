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

            if (reply->error() != QNetworkReply::NoError) {
                reason = http > 0
                       ? tr("HTTP %1 — %2").arg(http).arg(reply->errorString())
                       : reply->errorString();
            } else if (!parseFeed(body)) {
                // HTTP 200 with a body that is not an Atom feed. YouTube answers
                // this way when it serves a consent/error/bot-check page instead of
                // the feed, and treating it as success is exactly what made a failed
                // channel look like an empty one. Retry it like any other failure.
                reason = tr("invalid response (HTTP %1, %2 bytes)")
                         .arg(http).arg(body.size());
            }

            if (reason.isEmpty()) {
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

bool YtFeed::parseFeed(const QByteArray &xml)
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

    beginInsertRows(QModelIndex(), m_videos.size(), m_videos.size() + parsed.size() - 1);
    m_videos += parsed;
    endInsertRows();
    return true;
}

void YtFeed::failOne(const QString &channelId, const QString &reason)
{
    ++m_failed;
    m_lastError = reason;
    qWarning("YtFeed: channel %s GIVEN UP after retries — %s",
             qPrintable(channelId), qPrintable(reason));
    emit errorChanged();
    finishOne();
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
