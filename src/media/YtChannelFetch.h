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

#ifndef YTCHANNELFETCH_H
#define YTCHANNELFETCH_H

#include <QObject>
#include <QString>
#include <QVector>
#include <functional>

#include "YtFeedCache.h"

class QNetworkAccessManager;
class QNetworkReply;

// One channel's recent videos, from whichever source still answers.
//
// Two places need exactly this — YtFeed, when a page asks for a channel's
// videos, and YtSubscriptions, whose startup pass fetches every channel to count
// the unseen ones and to fill the cache — so the order of sources lives here,
// once:
//
//   1. the public RSS feed (~5 KB). Dead since 2026-09-05 (404 for every
//      channel, from every network) but tried first, and free the day it comes
//      back;
//   2. the list saved on disk, if it is younger than maxCacheAgeMs. This is what
//      keeps a screenful of channels from costing megabytes every time the Home
//      page is opened;
//   3. the web client's own InnerTube endpoint (~115 KB), keyless, the same one
//      the in-app search talks to.
//
// The caller gets one Result and decides what to do with it: none of the three
// sources is a special case downstream, they only differ in `source` (which the
// UI turns into the "this list is not fresh" notice) and in whether the caller
// writes the cache.
class YtChannelFetch : public QObject
{
    Q_OBJECT

public:
    struct Result {
        enum Source { Rss, InnerTube, Cache, Failed };
        QString channelId;
        QVector<YtVideo> videos;
        Source source = Failed;
        qint64 savedAt = 0;     // when source == Cache: when it was saved (ms)
        QString error;          // why the network sources gave up (for the UI)
    };

    // Fetch `channelId` and hand the result to `done`. Serve step 2 (the saved
    // list) only if it is younger than maxCacheAgeMs; pass 0 to always go to the
    // network, and note that a cache older than that is NOT returned here — the
    // caller still has YtFeedCache::read() for its own last-resort fallback.
    // The job is parented to `context` and deletes itself when it finishes, so a
    // caller that dies mid-flight takes its pending fetches with it.
    static void start(QNetworkAccessManager *nam, const QString &channelId,
                      qint64 maxCacheAgeMs, QObject *context,
                      std::function<void(const Result &)> done);

private:
    YtChannelFetch(QNetworkAccessManager *nam, const QString &channelId,
                   qint64 maxCacheAgeMs, QObject *context,
                   std::function<void(const Result &)> done);

    void fetchRss();
    void fetchBrowse();
    void deliver(const Result &r);
    // A reply bounded by a timeout — Qt 5.6 has no setTransferTimeout, and a
    // stalled mobile connection would otherwise hold the slot forever.
    QNetworkReply *send(QNetworkReply *reply, int timeoutMs);

    QNetworkAccessManager *m_nam;
    QString m_channelId;
    qint64 m_maxCacheAge;
    std::function<void(const Result &)> m_done;
    QString m_error;
};

#endif // YTCHANNELFETCH_H
