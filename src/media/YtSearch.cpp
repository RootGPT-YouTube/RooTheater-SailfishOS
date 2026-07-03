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

#include "YtSearch.h"

#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonValue>
#include <QUrl>
#include <QUrlQuery>
#include <QLocale>

// The per-site UA the system browser sends to youtube.com (its ua-update.json);
// same string YtPlayerPage uses. Without the "like Chrome" token YouTube serves
// degraded pages.
static const char kYouTubeUA[] =
    "Mozilla/5.0 (Sailfish 5.0; Mobile; rv:91.0) Gecko/91.0 Firefox/91.0 "
    "like Chrome/135.0.0.0 Safari/537.36";

YtSearch::YtSearch(QObject *parent)
    : QAbstractListModel(parent)
    , m_nam(new QNetworkAccessManager(this))
{
}

YtSearch::~YtSearch() = default;

int YtSearch::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_items.size();
}

QVariant YtSearch::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size())
        return QVariant();
    const Item &it = m_items.at(index.row());
    switch (role) {
    case KindRole:        return it.isChannel ? QStringLiteral("channel") : QStringLiteral("video");
    case VideoIdRole:     return it.videoId;
    case TitleRole:       return it.title;
    case ThumbnailRole:   return it.thumbnail;
    case ChannelIdRole:   return it.channelId;
    case ChannelNameRole: return it.channelName;
    case DetailRole:      return it.detail;
    case WatchUrlRole:    return QStringLiteral("https://www.youtube.com/watch?v=") + it.videoId;
    default:              return QVariant();
    }
}

QHash<int, QByteArray> YtSearch::roleNames() const
{
    return {
        { KindRole,        "kind" },
        { VideoIdRole,     "videoId" },
        { TitleRole,       "title" },
        { ThumbnailRole,   "thumbnail" },
        { ChannelIdRole,   "channelId" },
        { ChannelNameRole, "channelName" },
        { DetailRole,      "detail" },
        { WatchUrlRole,    "watchUrl" }
    };
}

void YtSearch::clear()
{
    ++m_generation;
    setLoading(false);
    if (!m_items.isEmpty()) {
        beginResetModel();
        m_items.clear();
        endResetModel();
        emit countChanged();
    }
}

void YtSearch::clearSuggestions()
{
    ++m_suggestGen;
    if (!m_suggestions.isEmpty()) {
        m_suggestions.clear();
        emit suggestionsChanged();
    }
}

QByteArray YtSearch::filterParams(int filter)
{
    // Standard results-page filter tokens (base64 of a tiny proto:
    // type=video / type=channel). Same value goes in the page's "sp" query
    // parameter and InnerTube's "params" field.
    switch (filter) {
    case FilterVideos:   return QByteArrayLiteral("EgIQAQ==");
    case FilterChannels: return QByteArrayLiteral("EgIQAg==");
    default:             return QByteArray();
    }
}

void YtSearch::search(const QString &query, int filter)
{
    const QString q = query.trimmed();
    ++m_generation;
    if (q.isEmpty()) {
        clear();
        return;
    }
    setLoading(true);
    searchInnerTube(q, filter, m_generation);
}

// ── primary: the web client's own search endpoint (keyless) ─────────────────

void YtSearch::searchInnerTube(const QString &query, int filter, int gen)
{
    QNetworkRequest req(QUrl(QStringLiteral(
        "https://www.youtube.com/youtubei/v1/search?prettyPrint=false")));
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    req.setHeader(QNetworkRequest::UserAgentHeader, QString::fromLatin1(kYouTubeUA));
    req.setAttribute(QNetworkRequest::FollowRedirectsAttribute, true);

    // Identify as the mobile-web client; hl/gl localize titles & relative dates.
    const QString locale = QLocale::system().name();          // e.g. "it_IT"
    const QString hl = locale.section(QLatin1Char('_'), 0, 0);
    const QString gl = locale.section(QLatin1Char('_'), 1, 1);
    QJsonObject client {
        { QStringLiteral("clientName"),    QStringLiteral("MWEB") },
        { QStringLiteral("clientVersion"), QStringLiteral("2.20250630.01.00") }
    };
    if (!hl.isEmpty()) client.insert(QStringLiteral("hl"), hl);
    if (!gl.isEmpty()) client.insert(QStringLiteral("gl"), gl);
    QJsonObject body {
        { QStringLiteral("context"), QJsonObject{ { QStringLiteral("client"), client } } },
        { QStringLiteral("query"), query }
    };
    const QByteArray params = filterParams(filter);
    if (!params.isEmpty())
        body.insert(QStringLiteral("params"), QString::fromLatin1(params));

    QNetworkReply *reply = m_nam->post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this, [this, reply, query, filter, gen]() {
        reply->deleteLater();
        if (gen != m_generation)
            return;                              // superseded by a newer search
        bool ok = false;
        if (reply->error() == QNetworkReply::NoError) {
            const QJsonObject root = QJsonDocument::fromJson(reply->readAll()).object();
            ok = applyResults(root) > 0;         // 0 parsed → try the scrape too
        }
        if (!ok)
            searchScrape(query, filter, gen);    // fallback B
    });
}

// ── fallback: scrape the mobile results page's embedded ytInitialData ───────

void YtSearch::searchScrape(const QString &query, int filter, int gen)
{
    QUrl url(QStringLiteral("https://m.youtube.com/results"));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("search_query"), query);
    const QByteArray params = filterParams(filter);
    if (!params.isEmpty())
        q.addQueryItem(QStringLiteral("sp"), QString::fromLatin1(params));
    url.setQuery(q);

    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader, QString::fromLatin1(kYouTubeUA));
    req.setAttribute(QNetworkRequest::FollowRedirectsAttribute, true);
    // Pre-set EU consent so we get results instead of the consent interstitial.
    req.setRawHeader("Cookie", "SOCS=CAI");

    QNetworkReply *reply = m_nam->get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply, gen]() {
        reply->deleteLater();
        if (gen != m_generation)
            return;
        if (reply->error() != QNetworkReply::NoError) {
            setLoading(false);
            emit error(reply->errorString());
            return;
        }
        const QByteArray html = reply->readAll();
        // ytInitialData sits in the page as a single-quoted, hex-escaped JS
        // string: ytInitialData = '\x7b\x22…';
        const QByteArray marker = QByteArrayLiteral("ytInitialData = '");
        const int start = html.indexOf(marker);
        int end = -1;
        if (start >= 0) {
            int i = start + marker.size();
            while ((i = html.indexOf('\'', i)) >= 0) {
                int bs = 0;
                for (int k = i - 1; k >= 0 && html.at(k) == '\\'; --k)
                    ++bs;
                if ((bs % 2) == 0) { end = i; break; }   // unescaped quote
                ++i;
            }
        }
        int found = 0;
        if (end > start) {
            const QByteArray json =
                decodeJsString(html.mid(start + marker.size(), end - start - marker.size()));
            found = applyResults(QJsonDocument::fromJson(json).object());
        }
        if (found == 0) {
            finishWith(QVector<Item>());         // clear + stop the spinner
            emit error(tr("No results"));
        }
    });
}

QByteArray YtSearch::decodeJsString(const QByteArray &raw)
{
    QByteArray out;
    out.reserve(raw.size());
    auto hex = [](char c) -> int {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        return -1;
    };
    for (int i = 0; i < raw.size(); ++i) {
        const char c = raw.at(i);
        if (c != '\\' || i + 1 >= raw.size()) {
            out.append(c);
            continue;
        }
        const char e = raw.at(++i);
        switch (e) {
        case 'x': {                              // \xNN → one byte (UTF-8 bytes)
            if (i + 2 < raw.size()) {
                const int h = hex(raw.at(i + 1)), l = hex(raw.at(i + 2));
                if (h >= 0 && l >= 0) { out.append(char((h << 4) | l)); i += 2; }
            }
            break;
        }
        case 'u': {                              // \uNNNN → UTF-16 unit → UTF-8
            if (i + 4 < raw.size()) {
                int v = 0; bool okhex = true;
                for (int k = 1; k <= 4; ++k) {
                    const int d = hex(raw.at(i + k));
                    if (d < 0) { okhex = false; break; }
                    v = (v << 4) | d;
                }
                if (okhex) {
                    i += 4;
                    QChar ch(v);
                    // Combine a surrogate pair if one follows.
                    if (ch.isHighSurrogate() && i + 6 < raw.size()
                            && raw.at(i + 1) == '\\' && raw.at(i + 2) == 'u') {
                        int v2 = 0; bool ok2 = true;
                        for (int k = 3; k <= 6; ++k) {
                            const int d = hex(raw.at(i + k));
                            if (d < 0) { ok2 = false; break; }
                            v2 = (v2 << 4) | d;
                        }
                        if (ok2 && QChar::isLowSurrogate(v2)) {
                            const QChar pair[2] = { ch, QChar(v2) };
                            out.append(QString(pair, 2).toUtf8());
                            i += 6;
                            break;
                        }
                    }
                    out.append(QString(ch).toUtf8());
                }
            }
            break;
        }
        case 'n': out.append('\n'); break;
        case 't': out.append('\t'); break;
        case 'r': out.append('\r'); break;
        default:  out.append(e);    break;       // \' \" \\ \/ …
        }
    }
    return out;
}

// ── shared renderer parsing ──────────────────────────────────────────────────

QString YtSearch::textOf(const QJsonValue &v)
{
    // YouTube text objects are either {"simpleText": "…"} or
    // {"runs": [{"text": "…"}, …]}.
    const QJsonObject o = v.toObject();
    const QString simple = o.value(QStringLiteral("simpleText")).toString();
    if (!simple.isEmpty())
        return simple;
    QString out;
    const QJsonArray runs = o.value(QStringLiteral("runs")).toArray();
    for (const QJsonValue &r : runs)
        out += r.toObject().value(QStringLiteral("text")).toString();
    return out;
}

void YtSearch::collect(const QJsonValue &node, QVector<Item> &channels, QVector<Item> &videos) const
{
    if (node.isArray()) {
        const QJsonArray a = node.toArray();
        for (const QJsonValue &v : a)
            collect(v, channels, videos);
        return;
    }
    if (!node.isObject())
        return;
    const QJsonObject o = node.toObject();

    // Videos: the mobile client's renderer.
    if (o.contains(QStringLiteral("videoWithContextRenderer"))) {
        const QJsonObject v = o.value(QStringLiteral("videoWithContextRenderer")).toObject();
        Item it;
        it.videoId = v.value(QStringLiteral("videoId")).toString();
        it.title = textOf(v.value(QStringLiteral("headline")));
        it.channelName = textOf(v.value(QStringLiteral("shortBylineText")));
        const QString len = textOf(v.value(QStringLiteral("lengthText")));
        const QString age = textOf(v.value(QStringLiteral("publishedTimeText")));
        it.detail = len.isEmpty() ? age
                  : age.isEmpty() ? len
                  : len + QStringLiteral("  ·  ") + age;
        // Channel id rides on the byline's navigation endpoint.
        const QJsonArray runs = v.value(QStringLiteral("shortBylineText")).toObject()
                                 .value(QStringLiteral("runs")).toArray();
        if (!runs.isEmpty())
            it.channelId = runs.first().toObject()
                    .value(QStringLiteral("navigationEndpoint")).toObject()
                    .value(QStringLiteral("browseEndpoint")).toObject()
                    .value(QStringLiteral("browseId")).toString();
        if (!it.videoId.isEmpty()) {
            it.thumbnail = QStringLiteral("https://i.ytimg.com/vi/%1/mqdefault.jpg").arg(it.videoId);
            videos.append(it);
        }
        return;   // don't descend into the renderer again
    }

    // Channels: compact (mobile) or full (desktop) renderer, same essentials.
    const bool compactChan = o.contains(QStringLiteral("compactChannelRenderer"));
    if (compactChan || o.contains(QStringLiteral("channelRenderer"))) {
        const QJsonObject c = o.value(compactChan ? QStringLiteral("compactChannelRenderer")
                                                  : QStringLiteral("channelRenderer")).toObject();
        Item it;
        it.isChannel = true;
        it.channelId = c.value(QStringLiteral("channelId")).toString();
        it.title = textOf(c.value(QStringLiteral("displayName")));
        if (it.title.isEmpty())
            it.title = textOf(c.value(QStringLiteral("title")));
        it.channelName = it.title;
        // On MWEB subscriberCountText holds the @handle and videoCountText the
        // subscriber count; show whatever is there.
        const QString a = textOf(c.value(QStringLiteral("subscriberCountText")));
        const QString b = textOf(c.value(QStringLiteral("videoCountText")));
        it.detail = a.isEmpty() ? b
                  : b.isEmpty() ? a
                  : a + QStringLiteral("  ·  ") + b;
        const QJsonArray thumbs = c.value(QStringLiteral("thumbnail")).toObject()
                                   .value(QStringLiteral("thumbnails")).toArray();
        if (!thumbs.isEmpty()) {
            QString u = thumbs.last().toObject().value(QStringLiteral("url")).toString();
            if (u.startsWith(QLatin1String("//")))
                u.prepend(QLatin1String("https:"));
            it.thumbnail = u;
        }
        if (!it.channelId.isEmpty())
            channels.append(it);
        return;
    }

    for (const QJsonValue &v : o)
        collect(v, channels, videos);
}

int YtSearch::applyResults(const QJsonObject &root)
{
    QVector<Item> channels, videos;
    collect(QJsonValue(root), channels, videos);
    if (channels.isEmpty() && videos.isEmpty())
        return 0;
    finishWith(channels + videos);               // channels first, then videos
    return channels.size() + videos.size();
}

void YtSearch::finishWith(const QVector<Item> &items)
{
    beginResetModel();
    m_items = items;
    endResetModel();
    emit countChanged();
    setLoading(false);
}

void YtSearch::setLoading(bool on)
{
    if (m_loading != on) {
        m_loading = on;
        emit loadingChanged();
    }
}

// ── keyless autocomplete ─────────────────────────────────────────────────────

void YtSearch::suggest(const QString &prefix)
{
    const QString p = prefix.trimmed();
    ++m_suggestGen;
    if (p.length() < 2) {
        clearSuggestions();
        return;
    }
    const int gen = m_suggestGen;

    QUrl url(QStringLiteral("https://suggestqueries-clients6.youtube.com/complete/search"));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("client"), QStringLiteral("youtube"));
    q.addQueryItem(QStringLiteral("ds"), QStringLiteral("yt"));
    const QString hl = QLocale::system().name().section(QLatin1Char('_'), 0, 0);
    if (!hl.isEmpty())
        q.addQueryItem(QStringLiteral("hl"), hl);
    q.addQueryItem(QStringLiteral("q"), p);
    url.setQuery(q);

    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader, QString::fromLatin1(kYouTubeUA));
    QNetworkReply *reply = m_nam->get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply, gen]() {
        reply->deleteLater();
        if (gen != m_suggestGen || reply->error() != QNetworkReply::NoError)
            return;
        // JSONP: window.google.ac.h(["prefix",[["suggestion",0,[…]],…],{…}])
        const QByteArray body = reply->readAll();
        const int l = body.indexOf('(');
        const int r = body.lastIndexOf(')');
        if (l < 0 || r <= l)
            return;
        const QJsonArray root = QJsonDocument::fromJson(body.mid(l + 1, r - l - 1)).array();
        QStringList out;
        const QJsonArray list = root.at(1).toArray();
        for (const QJsonValue &v : list) {
            const QString s = v.toArray().at(0).toString();
            if (!s.isEmpty())
                out << s;
            if (out.size() >= 8)
                break;
        }
        if (out != m_suggestions) {
            m_suggestions = out;
            emit suggestionsChanged();
        }
    });
}
