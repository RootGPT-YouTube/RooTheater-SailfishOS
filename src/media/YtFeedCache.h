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

#ifndef YTFEEDCACHE_H
#define YTFEEDCACHE_H

#include <QString>
#include <QVector>
#include <QByteArray>

// One video as it comes out of a channel's RSS feed, and the last good list of
// them kept on disk per channel.
//
// The parsing and the cache live here, apart from the model, because two
// different places produce that list: YtFeed, when a page asks for a channel's
// videos, and YtSubscriptions, which fetches the very same feeds at startup to
// count the unseen videos for the Home badges. That startup pass now also fills
// the cache, so a channel has a list saved for it BEFORE it is ever opened —
// without it, the first time YouTube's feed service goes down (404/500 on every
// channel, see YtFeed::failOne) a channel never opened had nothing to fall back
// on and showed only an error.
struct YtVideo {
    QString videoId;
    QString title;
    QString thumbnail;
    QString channelId;
    QString channelName;
    qint64 published = 0;   // ms since epoch
};

namespace YtFeedCache {

// Parse a channel's Atom feed. Returns false when the body is not a usable feed:
// a channel with zero uploads is a success with nothing in `out`, a consent /
// error / bot-check page is a failure (YouTube serves those with HTTP 200, and
// taking them for success is what made a failed channel look like an empty one).
bool parseFeed(const QByteArray &xml, QVector<YtVideo> *out);

// ── the replacement source ───────────────────────────────────────────────────
// Since 2026-09-05 https://www.youtube.com/feeds/videos.xml answers 404 for
// EVERY channel — YouTube's own included — from any network, while the site
// itself works: the RSS service is gone, not our request. The same list is
// still served, keylessly, by the web client's own InnerTube endpoint, which is
// what the in-app search already talks to (YtSearch). browseUrl()/browseBody()
// build that request for one channel's "Videos" tab and parseBrowse() reads the
// answer into the very same YtVideo list, so everything downstream — the model,
// the cache, the unseen badges — is unchanged.
//
// It costs ~115 KB per channel against the RSS's ~5 KB, so callers ask for it
// only when the feed has actually failed and the saved list is too old to serve.
QString browseUrl();
QByteArray browseBody(const QString &channelId);
bool parseBrowse(const QByteArray &json, QVector<YtVideo> *out);

// InnerTube dates a video the way the site does — "2 giorni fa", "2 days ago" —
// so the exact publication instant the RSS carried is gone. This turns that
// phrase into an approximate ms-since-epoch (0 when it cannot be read), which is
// enough to sort the merged list and to decide what counts as unseen.
qint64 relativeToEpoch(const QString &text, qint64 nowMs);

// Where a channel's saved list lives. Spelled out rather than taken from
// QStandardPaths::AppCacheLocation — see the .cpp.
QString path(const QString &channelId);

// Save / load the last good list for a channel. read() reports the save time in
// `savedAt` (ms epoch, 0 when unknown) — the date the UI puts on its notice.
void write(const QString &channelId, const QVector<YtVideo> &vids);
QVector<YtVideo> read(const QString &channelId, qint64 *savedAt = nullptr);

}   // namespace YtFeedCache

#endif // YTFEEDCACHE_H
