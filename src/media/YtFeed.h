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

    // Fetch the RSS feeds of these channel ids and show their videos merged and
    // sorted newest-first. Re-callable (replaces the current contents).
    Q_INVOKABLE void loadChannels(const QStringList &channelIds);

signals:
    void loadingChanged();
    void countChanged();
    void errorChanged();

private:
    struct Video {
        QString videoId;
        QString title;
        QString thumbnail;
        QString channelId;
        QString channelName;
        qint64 published = 0;   // ms since epoch
    };

    // Returns false when the body is not a usable Atom feed (see the .cpp): a
    // channel with zero uploads is a success, a consent/error page is not.
    // Parses into `out` and adds nothing to the model: the caller decides what
    // to do with the result, because it also has to save it to the cache.
    bool parseFeed(const QByteArray &xml, QVector<Video> *out) const;
    void appendVideos(const QVector<Video> &vids);

    // Last good list per channel, kept on disk. The path is spelled out rather
    // than taken from QStandardPaths::AppCacheLocation — see the .cpp.
    static QString cachePath(const QString &channelId);
    void writeCache(const QString &channelId, const QVector<Video> &vids) const;
    QVector<Video> readCache(const QString &channelId, qint64 *savedAt) const;
    void finishOne();
    void failOne(const QString &channelId, const QString &reason);
    void startNext(int gen);    // launch queued fetches up to the concurrency cap

    QVector<Video> m_videos;
    QNetworkAccessManager *m_nam = nullptr;
    int m_pending = 0;          // feeds not yet parsed (for the loading flag)
    int m_generation = 0;       // bumped on each loadChannels → drop stale replies
    QStringList m_idQueue;      // channel ids still to fetch
    int m_active = 0;           // in-flight requests (bounded, see startNext)
    QHash<QString, int> m_retries;  // per-channel retry count (transient failures)
    int m_failed = 0;               // channels given up on in this load
    QString m_lastError;            // reason shown in the UI for the last failure
    int m_stale = 0;                // channels served from the on-disk cache
    qint64 m_staleSince = 0;        // oldest cache used in this load (ms, 0 = none)
};

#endif // YTFEED_H
