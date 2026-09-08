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

#ifndef YTFEED_H
#define YTFEED_H

#include <QAbstractListModel>
#include <QString>
#include <QVector>
#include <QStringList>
#include <QDateTime>
#include <QHash>

#include "YtFeedCache.h"

class QNetworkAccessManager;
class QNetworkReply;

// YtFeed is the list of recent videos from one or more subscribed channels,
// built from each channel's PUBLIC RSS feed
// (https://www.youtube.com/feeds/videos.xml?channel_id=UC…) — no Data API, no
// quota. loadChannels() fetches all the given channels' feeds, merges the
// entries and sorts them newest-first. Used both for the aggregated "YouTube"
// page (all subscriptions) and a single channel's page.
class YtFeed : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    // Channels whose feed could not be fetched in this load, and a human-readable
    // reason for the last one. A failed fetch used to be indistinguishable from a
    // channel with no videos (both showed an empty list and no message), which made
    // a transient YouTube/network failure look like the app losing the channel.
    Q_PROPERTY(int failedCount READ failedCount NOTIFY errorChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY errorChanged)
    // A channel whose feed cannot be fetched is served from the last list saved
    // for it instead of showing an empty page (see failOne in the .cpp for why
    // that list is still worth showing). staleCount is how many channels came
    // from disk in this load; staleSince is the OLDEST of those saves, in ms
    // since epoch, 0 when none — the date the UI puts on its "not fresh" notice.
    Q_PROPERTY(int staleCount READ staleCount NOTIFY errorChanged)
    Q_PROPERTY(qint64 staleSince READ staleSince NOTIFY errorChanged)

public:
    enum Roles {
        VideoIdRole = Qt::UserRole + 1,
        TitleRole,
        ThumbnailRole,
        ChannelIdRole,
        ChannelNameRole,
        PublishedRole,      // ms since epoch (for relative-time formatting in QML)
        WatchUrlRole
    };

    explicit YtFeed(QObject *parent = nullptr);
    ~YtFeed() override;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool loading() const { return m_pending > 0; }
    int count() const { return m_videos.size(); }
    int failedCount() const { return m_failed; }
    QString lastError() const { return m_lastError; }
    int staleCount() const { return m_stale; }
    qint64 staleSince() const { return m_staleSince; }

    // Fetch these channels and show their videos merged and sorted newest-first.
    // Re-callable (replaces the current contents). `force` is the user asking for
    // it — a pull-to-refresh — and goes past the saved list even when it is
    // recent; the automatic load takes the cheap route (see startNext).
    Q_INVOKABLE void loadChannels(const QStringList &channelIds, bool force = false);

signals:
    void loadingChanged();
    void countChanged();
    void errorChanged();

private:
    // Parsing and the on-disk "last good list" per channel live in YtFeedCache:
    // YtSubscriptions fills the same cache during its startup unseen pass, so a
    // channel has a list saved for it before it is ever opened.
    void appendVideos(const QVector<YtVideo> &vids);
    void finishOne();
    void failOne(const QString &channelId, const QString &reason);
    void startNext(int gen);    // launch queued fetches up to the concurrency cap

    QVector<YtVideo> m_videos;
    QNetworkAccessManager *m_nam = nullptr;
    int m_pending = 0;          // feeds not yet parsed (for the loading flag)
    int m_generation = 0;       // bumped on each loadChannels → drop stale replies
    bool m_force = false;       // this load was asked for by hand: no cache shortcut
    QStringList m_idQueue;      // channel ids still to fetch
    int m_active = 0;           // in-flight requests (bounded, see startNext)
    QHash<QString, int> m_retries;  // per-channel retry count (transient failures)
    int m_failed = 0;               // channels given up on in this load
    QString m_lastError;            // reason shown in the UI for the last failure
    int m_stale = 0;                // channels served from the on-disk cache
    qint64 m_staleSince = 0;        // oldest cache used in this load (ms, 0 = none)
};

#endif // YTFEED_H
