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
#include "YtChannelFetch.h"

#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QUrl>
#include <QTimer>
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
    const YtVideo &v = m_videos.at(index.row());
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

void YtFeed::loadChannels(const QStringList &channelIds, bool force)
{
    m_force = force;
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
    // Cap concurrent fetches: firing dozens of parallel TLS requests at once
    // spikes memory/fds and can crash the app on a constrained device.
    const int kMax = 6;
    // A transient error (TLS reset, DNS blip, rate-limit) would otherwise drop a
    // channel silently; one re-queued retry lets "reload" (and the initial load)
    // recover instead of showing partial results. The per-request timeouts live
    // in YtChannelFetch.
    const int kRetryMax   = 1;
    const int kRetryDelay = 1000;
    // How old a saved list may be and still be served without asking the
    // network. It only comes into play when the RSS feed has already failed:
    // with the feed service down, every visit to the aggregated page would
    // otherwise re-download all the channels from InnerTube at ~115 KB each —
    // megabytes of mobile data for a list that changes a few times a day. A
    // pull-to-refresh (force) ignores it and goes straight to the network.
    const qint64 kFreshMs = m_force ? 0 : 2LL * 3600 * 1000;

    while (m_active < kMax && !m_idQueue.isEmpty()) {
        const QString id = m_idQueue.takeFirst();
        ++m_active;
        YtChannelFetch::start(m_nam, id, kFreshMs, this,
                              [this, id, gen, kRetryMax, kRetryDelay]
                              (const YtChannelFetch::Result &r) {
            if (gen != m_generation)
                return;         // superseded — leave the newer load's counters alone
            --m_active;

            if (r.source == YtChannelFetch::Result::Failed) {
                if (m_retries.value(id) < kRetryMax) {
                    // Re-queue this channel after a short backoff instead of
                    // counting it done and losing it.
                    m_retries[id] += 1;
                    qWarning("YtFeed: channel %s failed (%s) — retry %d/%d",
                             qPrintable(id), qPrintable(r.error),
                             m_retries.value(id), kRetryMax);
                    QTimer::singleShot(kRetryDelay * m_retries.value(id), this,
                                       [this, id, gen]() {
                        if (gen != m_generation)
                            return;
                        m_idQueue << id;
                        startNext(gen);
                    });
                    startNext(gen);
                    return;
                }
                failOne(id, r.error);   // give up: fall back to whatever is saved
            } else {
                appendVideos(r.videos);
                if (r.source == YtChannelFetch::Result::Cache) {
                    // Recent enough to serve as-is, but still not fresh: say so
                    // in the UI rather than let it pass for a live list.
                    ++m_stale;
                    if (m_staleSince == 0 || (r.savedAt > 0 && r.savedAt < m_staleSince))
                        m_staleSince = r.savedAt;
                    emit errorChanged();
                } else {
                    YtFeedCache::write(id, r.videos);   // keep the last good list
                }
                finishOne();
            }
            startNext(gen);     // fill the freed slot with the next queued channel
        });
    }
}

void YtFeed::appendVideos(const QVector<YtVideo> &vids)
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
    const QVector<YtVideo> cached = YtFeedCache::read(channelId, &savedAt);
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

void YtFeed::finishOne()
{
    if (m_pending > 0)
        --m_pending;
    if (m_pending == 0) {
        // All feeds in: sort newest-first and refresh the view in one shot.
        std::stable_sort(m_videos.begin(), m_videos.end(),
                         [](const YtVideo &a, const YtVideo &b) { return a.published > b.published; });
        beginResetModel();
        endResetModel();
        emit countChanged();
        emit loadingChanged();
        if (m_failed > 0)
            qWarning("YtFeed: load finished with %d video(s), %d channel(s) failed",
                     m_videos.size(), m_failed);
    }
}
