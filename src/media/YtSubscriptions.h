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

#ifndef YTSUBSCRIPTIONS_H
#define YTSUBSCRIPTIONS_H

#include <QAbstractListModel>
#include <QString>
#include <QVector>
#include <QStringList>
#include <QQueue>
#include <QSet>

class QNetworkAccessManager;
class QNetworkReply;

// YtSubscriptions is the list of followed YouTube channels, with ZERO Data API
// usage: channels are resolved keyless (the public channel page HTML + the oEmbed
// endpoint) and their new videos come from the public RSS feed (see YtFeed). It
// persists to a small JSON file and imports/exports the widely-used subscription
// JSON so exports from common YouTube frontends drop straight in.
//
// A single shared instance is exposed to QML as the `ytSubs` context property so
// the Home grid and the YouTube page stay in sync.
class YtSubscriptions : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    // True while a resolve/import network job is in flight (spinner in the UI).
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    // Background avatar/channel-id backfill progress (after an import or at
    // startup): filling==true while the queue drains, fillProgress in 0..1. The UI
    // shows a progress bar and reloads the feeds when fillFinished() fires.
    Q_PROPERTY(bool filling READ filling NOTIFY fillChanged)
    Q_PROPERTY(qreal fillProgress READ fillProgress NOTIFY fillChanged)
    // Subscriptions still without an avatar (or a resolved channel id): lets the
    // UI offer a "fetch the missing ones" action instead of waiting for a restart.
    Q_PROPERTY(int missingAvatars READ missingAvatars NOTIFY fillChanged)
    // Startup feed pass (see refreshUnseen): every channel's RSS is fetched, its
    // unseen count updated AND its video list saved to the feed cache. It is the
    // only thing that guarantees a channel has a list before it is first opened,
    // so the UI shows how far along it is — refreshProgress in 0..1 next to the
    // "YouTube RSS" header on Home.
    Q_PROPERTY(bool refreshing READ refreshing NOTIFY refreshChanged)
    Q_PROPERTY(qreal refreshProgress READ refreshProgress NOTIFY refreshChanged)
    // How the last finished pass went: channels answered vs channels on which
    // BOTH sources failed (the RSS feed and the InnerTube fallback). All of them
    // failing is the shape of a YouTube-side outage, and that is what the Home
    // page tells the user about when feedsRefreshed() fires.
    Q_PROPERTY(int refreshOk READ refreshOk NOTIFY refreshChanged)
    Q_PROPERTY(int refreshFailed READ refreshFailed NOTIFY refreshChanged)

public:
    enum Roles {
        ChannelIdRole = Qt::UserRole + 1,
        NameRole,
        AvatarRole,
        UrlRole,
        UnseenRole          // count of feed videos newer than the channel's lastSeen
    };

    explicit YtSubscriptions(QObject *parent = nullptr);
    ~YtSubscriptions() override;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return m_subs.size(); }
    bool busy() const { return m_busy; }
    bool filling() const { return m_fillTotal > 0; }
    qreal fillProgress() const { return m_fillTotal > 0 ? qreal(m_fillDone) / m_fillTotal : 0.0; }
    int missingAvatars() const;
    bool refreshing() const { return m_unseenTotal > 0; }
    qreal refreshProgress() const
    { return m_unseenTotal > 0 ? qreal(m_unseenDone) / m_unseenTotal : 0.0; }
    int refreshOk() const { return m_unseenOk; }
    int refreshFailed() const { return m_unseenFail; }

    // Queue every subscription that still misses an avatar/channel id and start
    // draining. Runs at startup, after an import, and on demand from the UI.
    Q_INVOKABLE void fillMissing();

    // Add a channel from a pasted URL/@handle (or a video URL → its channel).
    // Resolves channelId/name/avatar keyless, then appends + persists. No-op if
    // already subscribed. Emits added()/error() when the async resolve finishes.
    Q_INVOKABLE void addByUrl(const QString &url);

    // Add a channel whose id/name/avatar are ALREADY known (e.g. a search
    // result) — appends + persists synchronously, no network. No-op if already
    // subscribed. Emits added() like addByUrl.
    Q_INVOKABLE void addResolved(const QString &channelId, const QString &name,
                                 const QString &avatar);

    // Remove a subscription by channelId (persists).
    Q_INVOKABLE void remove(const QString &channelId);
    Q_INVOKABLE void removeList(const QStringList &channelIds);
    Q_INVOKABLE bool contains(const QString &channelId) const;

    // ── "unseen" badges ──────────────────────────────────────────────────────
    // Fetch every channel's RSS: set its unseen count = videos published after
    // the channel's lastSeen timestamp, and save its video list to the feed cache
    // (YtFeedCache) so the channel is never left without a list when YouTube's
    // feed service goes down. Bounded concurrency; updates rows as they arrive,
    // reports progress through refreshing/refreshProgress. Call on home/app
    // activation — a pass already running is left to finish.
    Q_INVOKABLE void refreshUnseen();
    // Mark a channel (or a set, or all) as seen: lastSeen = now, unseen = 0.
    Q_INVOKABLE void markSeen(const QString &channelId);
    Q_INVOKABLE void markSeenList(const QStringList &channelIds);
    Q_INVOKABLE void markAllSeen();

    // Channel ids of every subscription that has one resolved (fed to YtFeed).
    Q_INVOKABLE QStringList channelIds() const;

    // Import a subscriptions export. Accepts BOTH the subscriptions .json AND a
    // full-backup .zip, which holds a SQLite database whose `subscriptions` table
    // we read directly (name + url + avatar, so no background fill needed). File
    // path or file:// URL.
    Q_INVOKABLE void importFile(const QString &fileUrl);
    // Write the current subscriptions as a standard-format .json into the given
    // directory (path or file:// URL); returns the written file path ("" on error).
    Q_INVOKABLE QString exportToDir(const QString &dirUrl);

    // Extract the 11-char video id from any YouTube video URL, or "" if none.
    Q_INVOKABLE static QString videoIdFromUrl(const QString &url);

signals:
    void countChanged();
    void busyChanged();
    void fillChanged();
    void fillFinished();
    void refreshChanged();
    // The startup feed pass has drained: unseen counts settled and every channel
    // that answered now has a saved list.
    void feedsRefreshed();
    void added(const QString &name);
    void error(const QString &message);

private:
    struct Sub {
        QString channelId;   // UC… (may be empty until resolved from a handle url)
        QString name;
        QString avatar;      // channel avatar image URL (may be empty)
        QString url;         // canonical channel URL
        qint64 lastSeen = 0; // ms epoch; videos published after this are "unseen"
        int unseen = 0;      // transient count from the last refreshUnseen()
    };

    struct FillJob { QString channelId; QString url; int tries = 0; };

    void setBusy(bool on);
    void load();
    void save() const;
    QString storePath() const;
    int indexOfChannel(const QString &channelId) const;

    // Fetch the channel page at `channelPageUrl` and pull channelId/name/avatar
    // from its canonical link + og: meta. `addAfter` ⇒ subscribe on success.
    void fetchChannelMeta(const QString &channelPageUrl, bool addAfter);
    void appendSub(const Sub &s);
    // Sort m_subs: channels with an unseen badge (>0) first, each group ordered
    // alphabetically by name (locale-aware). Does NOT emit model signals —
    // callers wrap it in a reset (or run it before the view exists).
    void resort();
    // resort() wrapped in begin/endResetModel — use after unseen counts change.
    void resortWithReset();

    // Import from the subscriptions .json (already read into bytes).
    void importJson(const QByteArray &bytes);
    // Import from a full-backup .zip by reading its SQLite subscriptions table.
    void importZipDb(const QString &zipPath);
    // Common tail after a batch import: reset view, persist, notify, start fill.
    void finishImport(int addedCount);

    // Background fill for imported entries missing an avatar (and handle urls
    // missing a channelId): a couple of requests at a time so an import of a big
    // list doesn't hammer the network, each one bounded by a timeout and retried
    // rather than dropped — one stalled channel page must not stop the batch.
    void enqueueFill(const QString &channelId, const QString &url);
    void processFillQueue();
    void startFillJob(const FillJob &job);

    // Unseen-count refresh + feed prefetch: fetch channel RSS feeds (bounded
    // concurrency), count videos newer than each channel's lastSeen and cache
    // the list. finishUnseenOne() advances the progress and closes the pass.
    void startUnseenFetch();
    void finishUnseenOne();

    QVector<Sub> m_subs;
    QNetworkAccessManager *m_nam = nullptr;
    bool m_busy = false;

    QQueue<FillJob> m_fillQueue;
    QSet<QString> m_fillPending;  // keys (channelId or url) queued or in flight
    int m_fillActive = 0;  // requests currently in flight
    int m_fillTotal = 0;   // items in the current backfill batch
    int m_fillDone = 0;    // completed so far

    QStringList m_unseenQueue;  // channel ids awaiting an unseen-count fetch
    int m_unseenActive = 0;     // in-flight unseen fetches (bounded)
    QHash<QString, int> m_unseenRetries;  // per-channel retry count in this pass
    int m_unseenTotal = 0;      // channels in the current pass (0 = not running)
    int m_unseenDone = 0;       // channels finished in the current pass
    int m_unseenOk = 0;         // channels that answered in the last pass
    int m_unseenFail = 0;       // channels no source could serve in the last pass
};

#endif // YTSUBSCRIPTIONS_H
