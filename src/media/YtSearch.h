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

#ifndef YTSEARCH_H
#define YTSEARCH_H

#include <QAbstractListModel>
#include <QString>
#include <QStringList>
#include <QVector>

class QNetworkAccessManager;
class QJsonObject;
class QJsonValue;

// YtSearch searches YouTube for videos and channels with ZERO Data API usage
// (no key, no quota, no login) — the same constraint as the rest of the
// YouTube feature (YtFeed/YtSubscriptions).
//
// Primary path: the public web client's own search endpoint
// (youtubei/v1/search, "InnerTube") queried as the MWEB client — verified to
// answer without any API key, cookie or PoToken. Fallback path (if the
// endpoint ever changes shape or starts refusing us): scrape the
// m.youtube.com/results page, whose embedded ytInitialData holds the SAME
// renderer JSON, so both paths share one parser.
//
// This is search of public metadata only — playback stays on the official
// watch page (YtPlayerPage) with ads intact, per the project's YouTube values.
class YtSearch : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(QStringList suggestions READ suggestions NOTIFY suggestionsChanged)

public:
    // What to search for. Values map to the results-page "sp"/InnerTube
    // "params" filter tokens.
    enum Filter { FilterAll = 0, FilterVideos, FilterChannels };
    Q_ENUM(Filter)

    enum Roles {
        KindRole = Qt::UserRole + 1,   // "video" | "channel"
        VideoIdRole,
        TitleRole,                     // video title / channel name
        ThumbnailRole,                 // video thumb / channel avatar
        ChannelIdRole,
        ChannelNameRole,               // video byline; == title for channels
        DetailRole,                    // "duration · age" / handle+subscribers
        WatchUrlRole
    };

    explicit YtSearch(QObject *parent = nullptr);
    ~YtSearch() override;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool loading() const { return m_loading; }
    int count() const { return m_items.size(); }
    QStringList suggestions() const { return m_suggestions; }

    // Run a search (replaces current results). `filter` is a Filter value.
    Q_INVOKABLE void search(const QString &query, int filter);
    // Fetch keyless autocomplete suggestions for a prefix (async → suggestions).
    Q_INVOKABLE void suggest(const QString &prefix);
    Q_INVOKABLE void clearSuggestions();
    Q_INVOKABLE void clear();

signals:
    void loadingChanged();
    void countChanged();
    void suggestionsChanged();
    void error(const QString &message);

private:
    struct Item {
        bool isChannel = false;
        QString videoId;
        QString title;
        QString thumbnail;
        QString channelId;
        QString channelName;
        QString detail;
    };

    void searchInnerTube(const QString &query, int filter, int gen);
    void searchScrape(const QString &query, int filter, int gen);   // fallback B
    // Walk any renderer JSON (InnerTube response or ytInitialData) and collect
    // results. Returns the number of items found.
    int applyResults(const QJsonObject &root);
    void collect(const QJsonValue &node, QVector<Item> &channels, QVector<Item> &videos) const;
    void setLoading(bool on);
    void finishWith(const QVector<Item> &items);

    // Filter token for the results page / InnerTube ("" = no filter).
    static QByteArray filterParams(int filter);
    // Decode a single-quoted JS string literal's contents (\xNN / \uNNNN /
    // simple escapes) into UTF-8 bytes — the format ytInitialData uses on
    // m.youtube.com.
    static QByteArray decodeJsString(const QByteArray &raw);
    // Text of a YouTube "runs"/"simpleText" object.
    static QString textOf(const QJsonValue &v);

    QVector<Item> m_items;
    QStringList m_suggestions;
    QNetworkAccessManager *m_nam = nullptr;
    bool m_loading = false;
    int m_generation = 0;      // bumped per search → drop stale replies
    int m_suggestGen = 0;
};

#endif // YTSEARCH_H
