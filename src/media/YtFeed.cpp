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
#include <algorithm>

YtFeed::YtFeed(QObject *parent)
    : QAbstractListModel(parent)
    , m_nam(new QNetworkAccessManager(this))
{
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
    while (m_active < kMax && !m_idQueue.isEmpty()) {
        const QString id = m_idQueue.takeFirst();
        ++m_active;
        QUrl url(QStringLiteral("https://www.youtube.com/feeds/videos.xml?channel_id=") + id);
        QNetworkRequest req(url);
        req.setAttribute(QNetworkRequest::FollowRedirectsAttribute, true);
        QNetworkReply *reply = m_nam->get(req);
        connect(reply, &QNetworkReply::finished, this, [this, reply, gen]() {
            reply->deleteLater();
            --m_active;
            if (gen != m_generation)
                return;         // superseded by a newer loadChannels()
            if (reply->error() == QNetworkReply::NoError)
                parseFeed(reply->readAll());
            finishOne();
            startNext(gen);     // pull the next queued channel
        });
    }
}

void YtFeed::parseFeed(const QByteArray &xml)
{
    // YouTube channel RSS is Atom: <feed><entry>… with yt:/media: extensions.
    QXmlStreamReader xr(xml);
    QVector<Video> parsed;
    QString feedAuthor;

    while (!xr.atEnd() && !xr.hasError()) {
        if (xr.readNext() != QXmlStreamReader::StartElement)
            continue;

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

    if (parsed.isEmpty())
        return;
    beginInsertRows(QModelIndex(), m_videos.size(), m_videos.size() + parsed.size() - 1);
    m_videos += parsed;
    endInsertRows();
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
    }
}
