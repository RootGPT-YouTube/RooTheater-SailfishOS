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

#include "YtChannelFetch.h"

#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QTimer>
#include <QUrl>
#include <QDateTime>

namespace {

// The UA the RSS request has always carried: benign, and short enough not to
// look like a scraper.
const char *kFeedUA = "Mozilla/5.0 (RooTheater)";
// InnerTube answers the MWEB client, so the request has to look like the mobile
// web page asking for its own data.
const char *kMwebUA =
    "Mozilla/5.0 (Linux; Android 10; Mobile; rv:91.0) Gecko/91.0 Firefox/91.0";

const int kRssTimeoutMs    = 12000;
const int kBrowseTimeoutMs = 20000;   // ~115 KB against ~5 KB: give it more room

}   // namespace

void YtChannelFetch::start(QNetworkAccessManager *nam, const QString &channelId,
                           qint64 maxCacheAgeMs, QObject *context,
                           std::function<void(const Result &)> done)
{
    new YtChannelFetch(nam, channelId, maxCacheAgeMs, context, done);
}

YtChannelFetch::YtChannelFetch(QNetworkAccessManager *nam, const QString &channelId,
                               qint64 maxCacheAgeMs, QObject *context,
                               std::function<void(const Result &)> done)
    : QObject(context)
    , m_nam(nam)
    , m_channelId(channelId)
    , m_maxCacheAge(maxCacheAgeMs)
    , m_done(done)
{
    fetchRss();
}

QNetworkReply *YtChannelFetch::send(QNetworkReply *reply, int timeoutMs)
{
    QTimer *timer = new QTimer(reply);
    timer->setSingleShot(true);
    connect(timer, &QTimer::timeout, reply, &QNetworkReply::abort);
    timer->start(timeoutMs);
    return reply;
}

void YtChannelFetch::fetchRss()
{
    QNetworkRequest req(QUrl(
        QStringLiteral("https://www.youtube.com/feeds/videos.xml?channel_id=") + m_channelId));
    req.setAttribute(QNetworkRequest::FollowRedirectsAttribute, true);
    req.setHeader(QNetworkRequest::UserAgentHeader, QString::fromLatin1(kFeedUA));
    QNetworkReply *reply = send(m_nam->get(req), kRssTimeoutMs);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        const int http = reply->attribute(
                    QNetworkRequest::HttpStatusCodeAttribute).toInt();
        Result r;
        r.channelId = m_channelId;

        if (reply->error() == QNetworkReply::NoError
                && YtFeedCache::parseFeed(reply->readAll(), &r.videos)) {
            r.source = Result::Rss;
            deliver(r);
            return;
        }
        // HTTP 200 with a body that is not an Atom feed counts as a failure too:
        // YouTube answers that way with a consent/error page, and taking it for
        // success is what once made a failed channel look like an empty one.
        m_error = reply->error() != QNetworkReply::NoError
                ? (http > 0 ? tr("HTTP %1 — %2").arg(http).arg(reply->errorString())
                            : reply->errorString())
                : tr("invalid response (HTTP %1)").arg(http);

        // The feed is out: before spending ~115 KB on InnerTube, see whether the
        // list we already have on disk is recent enough to answer with.
        if (m_maxCacheAge > 0) {
            qint64 savedAt = 0;
            const QVector<YtVideo> cached = YtFeedCache::read(m_channelId, &savedAt);
            if (!cached.isEmpty() && savedAt > 0
                    && QDateTime::currentMSecsSinceEpoch() - savedAt < m_maxCacheAge) {
                r.videos = cached;
                r.source = Result::Cache;
                r.savedAt = savedAt;
                r.error = m_error;
                deliver(r);
                return;
            }
        }
        fetchBrowse();
    });
}

void YtChannelFetch::fetchBrowse()
{
    QNetworkRequest req{QUrl(YtFeedCache::browseUrl())};
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    req.setHeader(QNetworkRequest::UserAgentHeader, QString::fromLatin1(kMwebUA));
    req.setAttribute(QNetworkRequest::FollowRedirectsAttribute, true);
    QNetworkReply *reply = send(
        m_nam->post(req, YtFeedCache::browseBody(m_channelId)), kBrowseTimeoutMs);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        Result r;
        r.channelId = m_channelId;

        if (reply->error() == QNetworkReply::NoError
                && YtFeedCache::parseBrowse(reply->readAll(), &r.videos)) {
            r.source = Result::InnerTube;
            deliver(r);
            return;
        }
        const int http = reply->attribute(
                    QNetworkRequest::HttpStatusCodeAttribute).toInt();
        // Report the InnerTube failure: it is the source that matters now, and
        // "the feed is 404" would send anyone reading the log down the wrong path.
        r.source = Result::Failed;
        r.error = reply->error() != QNetworkReply::NoError
                ? (http > 0 ? tr("HTTP %1 — %2").arg(http).arg(reply->errorString())
                            : reply->errorString())
                : tr("unreadable answer (HTTP %1)").arg(http);
        deliver(r);
    });
}

void YtChannelFetch::deliver(const Result &r)
{
    if (m_done)
        m_done(r);
    deleteLater();
}
