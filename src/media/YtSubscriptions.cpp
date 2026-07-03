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

#include "YtSubscriptions.h"

#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QUrl>
#include <QUrlQuery>
#include <QRegularExpression>
#include <QFile>
#include <QDir>
#include <QStandardPaths>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QTimer>
#include <QFileInfo>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QDateTime>
#include <QXmlStreamReader>
#include <private/qzipreader_p.h>
#include <algorithm>

namespace {

const char *kBrowserUA =
    "Mozilla/5.0 (X11; Linux x86_64; rv:91.0) Gecko/20100101 Firefox/91.0";

// A YouTube channel id: "UC" + 22 url-safe base64 chars.
const QRegularExpression reChannelId(QStringLiteral("(UC[0-9A-Za-z_-]{22})"));

// Minimal HTML entity unescape for the few that show up in og:title.
QString unescape(QString s)
{
    s.replace(QLatin1String("&amp;"), QLatin1String("&"));
    s.replace(QLatin1String("&quot;"), QLatin1String("\""));
    s.replace(QLatin1String("&#39;"), QLatin1String("'"));
    s.replace(QLatin1String("&#x27;"), QLatin1String("'"));
    s.replace(QLatin1String("&lt;"), QLatin1String("<"));
    s.replace(QLatin1String("&gt;"), QLatin1String(">"));
    return s;
}

// Channel id straight from a /channel/UC… URL (no network), else "".
QString channelIdFromUrl(const QString &url)
{
    QRegularExpressionMatch m =
        QRegularExpression(QStringLiteral("youtube\\.com/channel/(UC[0-9A-Za-z_-]{22})"))
            .match(url);
    return m.hasMatch() ? m.captured(1) : QString();
}

// Pull the channel id out of channel-page HTML (canonical link → ytInitialData).
QString channelIdFromHtml(const QByteArray &html)
{
    const QString s = QString::fromUtf8(html);
    for (const QString &pat : {
             QStringLiteral("<link rel=\"canonical\" href=\"https://www\\.youtube\\.com/channel/(UC[0-9A-Za-z_-]{22})\""),
             QStringLiteral("\"externalId\":\"(UC[0-9A-Za-z_-]{22})\""),
             QStringLiteral("\"channelId\":\"(UC[0-9A-Za-z_-]{22})\"") }) {
        QRegularExpressionMatch m = QRegularExpression(pat).match(s);
        if (m.hasMatch())
            return m.captured(1);
    }
    return QString();
}

// Value of an og:/twitter: <meta> tag, tolerating either attribute order.
QString metaContent(const QString &html, const QString &prop)
{
    QRegularExpressionMatch m =
        QRegularExpression(QStringLiteral("<meta[^>]+property=\"%1\"[^>]+content=\"([^\"]*)\"").arg(prop))
            .match(html);
    if (m.hasMatch())
        return unescape(m.captured(1));
    m = QRegularExpression(QStringLiteral("<meta[^>]+content=\"([^\"]*)\"[^>]+property=\"%1\"").arg(prop))
            .match(html);
    return m.hasMatch() ? unescape(m.captured(1)) : QString();
}

// Channel names often carry decorative ornaments/emoji (꧁ ꧂, ★, 💀…) that the
// Sailfish system font has no glyph for → they render as ".notdef" tofu boxes.
// We can't add glyphs to the font, so strip the un-renderable decoration for
// DISPLAY only (the raw name is kept for export). Keeps letters/marks/numbers and
// ordinary punctuation of any script; drops symbol/emoji/format/ornament code
// points that fonts typically lack.
QString displayName(const QString &raw)
{
    QString out;
    const QVector<uint> ucs = raw.toUcs4();
    for (uint c : ucs) {
        if (c >= 0x1F000)                       continue; // astral emoji/symbols
        if (c >= 0x2190 && c <= 0x2BFF)         continue; // arrows/dingbats/misc symbols
        if (c >= 0xFE00 && c <= 0xFE0F)         continue; // variation selectors
        if (c >= 0xA9C0 && c <= 0xA9CF)         continue; // Javanese ornaments (꧁ ꧂)
        if (c == 0x200D)                        continue; // zero-width joiner
        const QChar::Category cat = QChar::category(c);
        if (cat == QChar::Symbol_Other || cat == QChar::Symbol_Modifier
                || cat == QChar::Other_NotAssigned || cat == QChar::Other_PrivateUse
                || cat == QChar::Other_Surrogate || cat == QChar::Other_Format)
            continue;
        out += QString::fromUcs4(&c, 1);
    }
    out = out.simplified();
    return out.isEmpty() ? raw : out;   // never blank out a name entirely
}

bool looksLikeChannelUrl(const QString &url)
{
    return url.contains(QLatin1String("youtube.com/channel/"))
        || url.contains(QLatin1String("youtube.com/@"))
        || url.contains(QLatin1String("youtube.com/c/"))
        || url.contains(QLatin1String("youtube.com/user/"));
}

} // namespace

YtSubscriptions::YtSubscriptions(QObject *parent)
    : QAbstractListModel(parent)
    , m_nam(new QNetworkAccessManager(this))
{
    load();
    // Backfill avatars (and channel ids) still missing from a previous import —
    // re-importing would skip already-subscribed channels, so heal them here.
    for (const Sub &s : m_subs)
        if (s.avatar.isEmpty() || s.channelId.isEmpty())
            enqueueFill(s.channelId, s.url);
    processFillQueue();
}

YtSubscriptions::~YtSubscriptions() = default;

// ── model ────────────────────────────────────────────────────────────────────

int YtSubscriptions::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_subs.size();
}

QVariant YtSubscriptions::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_subs.size())
        return QVariant();
    const Sub &s = m_subs.at(index.row());
    switch (role) {
    case ChannelIdRole: return s.channelId;
    case NameRole:      return displayName(s.name);   // strip un-renderable ornaments
    case AvatarRole:    return s.avatar;
    case UrlRole:       return s.url;
    case UnseenRole:    return s.unseen;
    default:            return QVariant();
    }
}

QHash<int, QByteArray> YtSubscriptions::roleNames() const
{
    return {
        { ChannelIdRole, "channelId" },
        { NameRole,      "name" },
        { AvatarRole,    "avatar" },
        { UrlRole,       "url" },
        { UnseenRole,    "unseen" }
    };
}

// ── helpers ──────────────────────────────────────────────────────────────────

void YtSubscriptions::setBusy(bool on)
{
    if (m_busy == on)
        return;
    m_busy = on;
    emit busyChanged();
}

int YtSubscriptions::indexOfChannel(const QString &channelId) const
{
    for (int i = 0; i < m_subs.size(); ++i)
        if (m_subs.at(i).channelId == channelId)
            return i;
    return -1;
}

bool YtSubscriptions::contains(const QString &channelId) const
{
    return !channelId.isEmpty() && indexOfChannel(channelId) >= 0;
}

QStringList YtSubscriptions::channelIds() const
{
    QStringList ids;
    for (const Sub &s : m_subs)
        if (!s.channelId.isEmpty())
            ids << s.channelId;
    return ids;
}

QString YtSubscriptions::storePath() const
{
    // The Sailjail sandbox (.desktop [X-Sailjail] OrganizationName/ApplicationName)
    // grants this app write access ONLY under its identity dir
    // ~/.config/com.github.RootGPT_YouTube/rootheater/ — NOT ~/.config/harbour-
    // rootheater/, which is what QStandardPaths::AppConfigLocation would give
    // (QCoreApplication::applicationName is "harbour-rootheater", org unset). Using
    // that unpermitted path made save() fail silently and subscriptions vanish on
    // restart. Build the permitted path explicitly instead.
    const QString base = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation);
    return base + QStringLiteral("/com.github.RootGPT_YouTube/rootheater/subscriptions.json");
}

QString YtSubscriptions::videoIdFromUrl(const QString &url)
{
    for (const QString &pat : {
             QStringLiteral("[?&]v=([0-9A-Za-z_-]{11})"),
             QStringLiteral("youtu\\.be/([0-9A-Za-z_-]{11})"),
             QStringLiteral("youtube\\.com/shorts/([0-9A-Za-z_-]{11})"),
             QStringLiteral("youtube\\.com/embed/([0-9A-Za-z_-]{11})") }) {
        QRegularExpressionMatch m = QRegularExpression(pat).match(url);
        if (m.hasMatch())
            return m.captured(1);
    }
    return QString();
}

void YtSubscriptions::resort()
{
    std::sort(m_subs.begin(), m_subs.end(), [](const Sub &a, const Sub &b) {
        // Channels with unseen videos float to the top; ties (and the seen
        // group) stay alphabetical.
        const bool au = a.unseen > 0;
        const bool bu = b.unseen > 0;
        if (au != bu)
            return au;
        return QString::localeAwareCompare(a.name, b.name) < 0;
    });
}

void YtSubscriptions::resortWithReset()
{
    beginResetModel();
    resort();
    endResetModel();
}

void YtSubscriptions::appendSub(const Sub &s)
{
    // Keep the list alphabetical: append then re-sort (a reset is simpler and
    // cheap for this list size than finding the sorted insert position).
    m_subs.append(s);
    resortWithReset();
    emit countChanged();
}

void YtSubscriptions::remove(const QString &channelId)
{
    const int i = indexOfChannel(channelId);
    if (i < 0)
        return;
    beginRemoveRows(QModelIndex(), i, i);
    m_subs.removeAt(i);
    endRemoveRows();
    emit countChanged();
    save();
}

void YtSubscriptions::removeList(const QStringList &channelIds)
{
    bool any = false;
    for (const QString &id : channelIds) {
        const int i = indexOfChannel(id);
        if (i < 0)
            continue;
        beginRemoveRows(QModelIndex(), i, i);
        m_subs.removeAt(i);
        endRemoveRows();
        any = true;
    }
    if (any) {
        emit countChanged();
        save();
    }
}

// ── unseen badges ────────────────────────────────────────────────────────────

void YtSubscriptions::markSeen(const QString &channelId)
{
    const int i = indexOfChannel(channelId);
    if (i < 0)
        return;
    m_subs[i].lastSeen = QDateTime::currentMSecsSinceEpoch();
    m_subs[i].unseen = 0;
    resortWithReset();   // badge cleared → drop out of the unseen-first group
    save();
}

void YtSubscriptions::markSeenList(const QStringList &channelIds)
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    bool any = false;
    for (const QString &id : channelIds) {
        const int i = indexOfChannel(id);
        if (i < 0)
            continue;
        m_subs[i].lastSeen = now;
        m_subs[i].unseen = 0;
        any = true;
    }
    if (any)
        resortWithReset();
    save();
}

void YtSubscriptions::markAllSeen()
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    for (int i = 0; i < m_subs.size(); ++i) {
        m_subs[i].lastSeen = now;
        m_subs[i].unseen = 0;
    }
    if (!m_subs.isEmpty())
        resortWithReset();
    save();
}

void YtSubscriptions::refreshUnseen()
{
    m_unseenQueue = channelIds();
    startUnseenFetch();
}

void YtSubscriptions::startUnseenFetch()
{
    const int kMax = 6;
    while (m_unseenActive < kMax && !m_unseenQueue.isEmpty()) {
        const QString id = m_unseenQueue.takeFirst();
        ++m_unseenActive;
        QNetworkRequest req(QUrl(
            QStringLiteral("https://www.youtube.com/feeds/videos.xml?channel_id=") + id));
        req.setAttribute(QNetworkRequest::FollowRedirectsAttribute, true);
        QNetworkReply *reply = m_nam->get(req);
        connect(reply, &QNetworkReply::finished, this, [this, reply, id]() {
            reply->deleteLater();
            --m_unseenActive;
            const int row = indexOfChannel(id);
            if (row >= 0 && reply->error() == QNetworkReply::NoError) {
                // Count <entry> items published after this channel's lastSeen.
                const qint64 since = m_subs[row].lastSeen;
                int n = 0;
                QXmlStreamReader xr(reply->readAll());
                while (!xr.atEnd() && !xr.hasError()) {
                    if (xr.readNext() == QXmlStreamReader::StartElement
                            && xr.name() == QLatin1String("published")) {
                        const QDateTime dt = QDateTime::fromString(xr.readElementText(), Qt::ISODate);
                        if (dt.isValid() && dt.toMSecsSinceEpoch() > since)
                            ++n;
                    }
                }
                if (n != m_subs[row].unseen) {
                    m_subs[row].unseen = n;
                    const QModelIndex mi = index(row, 0);
                    emit dataChanged(mi, mi, { UnseenRole });
                }
            }
            startUnseenFetch();
            // When the whole batch has drained, reorder so channels that gained
            // an unseen badge float to the top (badge>0 first, then alphabetical).
            if (m_unseenActive == 0 && m_unseenQueue.isEmpty())
                resortWithReset();
        });
    }
}

// ── add by URL (interactive) ─────────────────────────────────────────────────

void YtSubscriptions::addByUrl(const QString &rawUrl)
{
    const QString url = rawUrl.trimmed();
    if (url.isEmpty())
        return;

    // A video URL → resolve its channel via oEmbed (keyless), then the channel page.
    const QString vid = videoIdFromUrl(url);
    if (!vid.isEmpty()) {
        setBusy(true);
        QUrl oembed(QStringLiteral("https://www.youtube.com/oembed"));
        QUrlQuery q;
        q.addQueryItem(QStringLiteral("url"),
                       QStringLiteral("https://www.youtube.com/watch?v=") + vid);
        q.addQueryItem(QStringLiteral("format"), QStringLiteral("json"));
        oembed.setQuery(q);
        QNetworkRequest req(oembed);
        req.setAttribute(QNetworkRequest::FollowRedirectsAttribute, true);
        req.setHeader(QNetworkRequest::UserAgentHeader, QString::fromLatin1(kBrowserUA));
        QNetworkReply *reply = m_nam->get(req);
        connect(reply, &QNetworkReply::finished, this, [this, reply]() {
            reply->deleteLater();
            if (reply->error() != QNetworkReply::NoError) {
                setBusy(false);
                emit error(reply->errorString());
                return;
            }
            const QJsonObject o = QJsonDocument::fromJson(reply->readAll()).object();
            const QString author = o.value(QStringLiteral("author_url")).toString();
            if (author.isEmpty()) {
                setBusy(false);
                emit error(tr("Could not resolve the video's channel"));
                return;
            }
            fetchChannelMeta(author, true); // keeps busy until it finishes
        });
        return;
    }

    if (!looksLikeChannelUrl(url)) {
        emit error(tr("Not a YouTube channel or video URL"));
        return;
    }

    setBusy(true);
    fetchChannelMeta(url, true);
}

void YtSubscriptions::fetchChannelMeta(const QString &channelPageUrl, bool addAfter)
{
    QNetworkRequest req{QUrl(channelPageUrl)};
    req.setAttribute(QNetworkRequest::FollowRedirectsAttribute, true);
    req.setHeader(QNetworkRequest::UserAgentHeader, QString::fromLatin1(kBrowserUA));
    req.setRawHeader("Accept-Language", "en-US,en;q=0.9");
    QNetworkReply *reply = m_nam->get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply, channelPageUrl, addAfter]() {
        reply->deleteLater();
        setBusy(false);
        if (reply->error() != QNetworkReply::NoError) {
            emit error(reply->errorString());
            return;
        }
        const QByteArray html = reply->readAll();
        const QString s = QString::fromUtf8(html);

        QString id = channelIdFromHtml(html);
        if (id.isEmpty())
            id = channelIdFromUrl(channelPageUrl);
        if (id.isEmpty()) {
            emit error(tr("Could not find the channel id"));
            return;
        }
        if (contains(id)) {
            emit error(tr("Already subscribed"));
            return;
        }
        QString name = metaContent(s, QStringLiteral("og:title"));
        if (name.isEmpty())
            name = id;
        const QString avatar = metaContent(s, QStringLiteral("og:image"));

        Sub sub;
        sub.channelId = id;
        sub.name = name;
        sub.avatar = avatar;
        sub.url = QStringLiteral("https://www.youtube.com/channel/") + id;
        sub.lastSeen = QDateTime::currentMSecsSinceEpoch();  // new sub → no old backlog
        appendSub(sub);
        save();
        emit added(name);
    });
}

// ── import / export (subscriptions JSON / full-backup archive) ───────────────

void YtSubscriptions::importFile(const QString &fileUrl)
{
    const QString path = QUrl(fileUrl).isLocalFile() ? QUrl(fileUrl).toLocalFile() : fileUrl;
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        emit error(tr("Cannot open %1").arg(path));
        return;
    }
    const QByteArray magic = f.read(4);
    // A full backup is a ZIP ("PK\x03\x04"); a subscriptions export is plain JSON.
    // Route accordingly.
    if (magic.startsWith(QByteArrayLiteral("PK\x03\x04"))) {
        f.close();
        importZipDb(path);
        return;
    }
    f.seek(0);
    const QByteArray bytes = f.readAll();
    f.close();
    importJson(bytes);
}

void YtSubscriptions::importJson(const QByteArray &bytes)
{
    const QJsonObject root = QJsonDocument::fromJson(bytes).object();
    const QJsonArray arr = root.value(QStringLiteral("subscriptions")).toArray();
    if (arr.isEmpty()) {
        emit error(tr("No subscriptions found in the file"));
        return;
    }

    int addedCount = 0;
    for (const QJsonValue &v : arr) {
        const QJsonObject o = v.toObject();
        // service_id 0 == YouTube in the subscriptions format; skip other services.
        if (o.contains(QStringLiteral("service_id"))
                && o.value(QStringLiteral("service_id")).toInt() != 0)
            continue;
        const QString url = o.value(QStringLiteral("url")).toString();
        const QString name = o.value(QStringLiteral("name")).toString();
        if (url.isEmpty())
            continue;
        const QString id = channelIdFromUrl(url);
        if (!id.isEmpty() && contains(id))
            continue;

        Sub sub;
        sub.channelId = id;                 // "" for @handle urls → filled later
        sub.name = name.isEmpty() ? id : name;
        sub.url = id.isEmpty() ? url : (QStringLiteral("https://www.youtube.com/channel/") + id);
        sub.lastSeen = QDateTime::currentMSecsSinceEpoch();
        m_subs.append(sub);
        ++addedCount;
        enqueueFill(id, sub.url);           // fetch avatar (and id for handles)
    }
    finishImport(addedCount);
}

void YtSubscriptions::importZipDb(const QString &zipPath)
{
    QZipReader zip(zipPath);
    if (!zip.isReadable()) {
        emit error(tr("Cannot read the backup archive"));
        return;
    }
    // Find the SQLite database inside the archive by extension (no hardcoded
    // name): these backups carry a single *.db with a `subscriptions` table.
    QString dbName;
    const QVector<QZipReader::FileInfo> entries = zip.fileInfoList();
    for (const QZipReader::FileInfo &fi : entries) {
        if (fi.isFile && fi.filePath.endsWith(QLatin1String(".db"), Qt::CaseInsensitive)) {
            dbName = fi.filePath;
            break;
        }
    }
    const QByteArray dbBytes = dbName.isEmpty() ? QByteArray() : zip.fileData(dbName);
    if (dbBytes.isEmpty()) {
        emit error(tr("This backup has no subscriptions database — export a subscriptions file instead"));
        return;
    }
    // QSQLITE needs a real file: drop the extracted db in a temp path.
    const QString tmp = QDir::tempPath() + QStringLiteral("/rt_import_subs.db");
    {
        QFile out(tmp);
        if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            emit error(tr("Cannot stage the backup database"));
            return;
        }
        out.write(dbBytes);
        out.close();
    }

    int addedCount = 0;
    {
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"),
                                                    QStringLiteral("rt_import"));
        db.setDatabaseName(tmp);
        if (!db.open()) {
            QSqlDatabase::removeDatabase(QStringLiteral("rt_import"));
            QFile::remove(tmp);
            emit error(tr("Cannot open the backup database"));
            return;
        }
        QSqlQuery q(db);
        q.exec(QStringLiteral("SELECT url, name, avatar_url, service_id FROM subscriptions"));
        while (q.next()) {
            if (q.value(3).toInt() != 0)   // service_id 0 == YouTube
                continue;
            const QString url = q.value(0).toString();
            if (url.isEmpty())
                continue;
            const QString name = q.value(1).toString();
            const QString avatar = q.value(2).toString();
            const QString id = channelIdFromUrl(url);
            if (!id.isEmpty() && contains(id))
                continue;

            Sub sub;
            sub.channelId = id;
            sub.name = name.isEmpty() ? id : name;
            sub.avatar = avatar;           // backup already has the avatar url
            sub.url = id.isEmpty() ? url
                                   : (QStringLiteral("https://www.youtube.com/channel/") + id);
            sub.lastSeen = QDateTime::currentMSecsSinceEpoch();
            m_subs.append(sub);
            ++addedCount;
            // Resolve later when the backup lacked a channelId (@handle url) OR an
            // avatar (empty/expired in the DB) → fetch a fresh og:image.
            if (id.isEmpty() || avatar.isEmpty())
                enqueueFill(id, sub.url);
        }
        db.close();
    }
    QSqlDatabase::removeDatabase(QStringLiteral("rt_import"));
    QFile::remove(tmp);
    finishImport(addedCount);
}

void YtSubscriptions::finishImport(int addedCount)
{
    if (addedCount == 0) {
        emit error(tr("Nothing new to import"));
        return;
    }
    resortWithReset();
    emit countChanged();
    save();
    emit added(tr("%n channel(s)", "", addedCount));
    processFillQueue();
}

QString YtSubscriptions::exportToDir(const QString &dirUrl)
{
    QString dir = QUrl(dirUrl).isLocalFile() ? QUrl(dirUrl).toLocalFile() : dirUrl;
    if (dir.isEmpty())
        dir = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    QDir().mkpath(dir);
    const QString path = dir + QStringLiteral("/rootheater-subscriptions.json");

    QJsonArray arr;
    for (const Sub &s : m_subs) {
        QJsonObject o;
        o.insert(QStringLiteral("service_id"), 0);
        o.insert(QStringLiteral("url"), s.channelId.isEmpty()
                 ? s.url
                 : QStringLiteral("https://www.youtube.com/channel/") + s.channelId);
        o.insert(QStringLiteral("name"), s.name);
        arr.append(o);
    }
    QJsonObject root;
    root.insert(QStringLiteral("app_version"), QStringLiteral("RooTheater"));
    root.insert(QStringLiteral("app_version_int"), 0);
    root.insert(QStringLiteral("subscriptions"), arr);

    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        emit error(tr("Cannot write %1").arg(path));
        return QString();
    }
    f.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    f.close();
    return path;
}

// ── background avatar / handle fill ──────────────────────────────────────────

void YtSubscriptions::enqueueFill(const QString &channelId, const QString &url)
{
    m_fillQueue.enqueue({ channelId, url });
    ++m_fillTotal;
    emit fillChanged();
}

void YtSubscriptions::processFillQueue()
{
    if (m_filling)
        return;
    if (m_fillQueue.isEmpty()) {
        // Batch drained: reset the progress counters and let the UI reload feeds.
        if (m_fillTotal > 0) {
            m_fillTotal = 0;
            m_fillDone = 0;
            emit fillChanged();
            emit fillFinished();
        }
        return;
    }
    m_filling = true;
    const FillJob job = m_fillQueue.dequeue();

    QNetworkRequest req{QUrl(job.url)};
    req.setAttribute(QNetworkRequest::FollowRedirectsAttribute, true);
    req.setHeader(QNetworkRequest::UserAgentHeader, QString::fromLatin1(kBrowserUA));
    req.setRawHeader("Accept-Language", "en-US,en;q=0.9");
    QNetworkReply *reply = m_nam->get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply, job]() {
        reply->deleteLater();
        if (reply->error() == QNetworkReply::NoError) {
            const QByteArray html = reply->readAll();
            const QString s = QString::fromUtf8(html);
            QString id = job.channelId.isEmpty() ? channelIdFromHtml(html) : job.channelId;
            const QString avatar = metaContent(s, QStringLiteral("og:image"));

            // Match the row: by channelId when known, else by the (handle) url.
            int row = -1;
            for (int i = 0; i < m_subs.size(); ++i) {
                if ((!job.channelId.isEmpty() && m_subs.at(i).channelId == job.channelId)
                        || (job.channelId.isEmpty() && m_subs.at(i).url == job.url)) {
                    row = i; break;
                }
            }
            if (row >= 0) {
                if (!id.isEmpty()) {
                    m_subs[row].channelId = id;
                    m_subs[row].url = QStringLiteral("https://www.youtube.com/channel/") + id;
                }
                if (!avatar.isEmpty())
                    m_subs[row].avatar = avatar;
                const QModelIndex mi = index(row, 0);
                emit dataChanged(mi, mi);
                save();
            }
        }
        m_filling = false;
        ++m_fillDone;
        emit fillChanged();
        // Gentle pacing: next job after a short delay.
        QTimer::singleShot(400, this, [this]() { processFillQueue(); });
    });
}

// ── persistence ──────────────────────────────────────────────────────────────

void YtSubscriptions::load()
{
    QFile f(storePath());
    if (!f.open(QIODevice::ReadOnly))
        return;
    const QJsonObject root = QJsonDocument::fromJson(f.readAll()).object();
    f.close();
    const QJsonArray arr = root.value(QStringLiteral("subscriptions")).toArray();
    m_subs.clear();
    for (const QJsonValue &v : arr) {
        const QJsonObject o = v.toObject();
        Sub s;
        s.channelId = o.value(QStringLiteral("channel_id")).toString();
        if (s.channelId.isEmpty())
            s.channelId = channelIdFromUrl(o.value(QStringLiteral("url")).toString());
        s.name = o.value(QStringLiteral("name")).toString();
        s.avatar = o.value(QStringLiteral("avatar")).toString();
        s.url = o.value(QStringLiteral("url")).toString();
        s.lastSeen = qint64(o.value(QStringLiteral("last_seen")).toDouble());
        if (s.url.isEmpty() && !s.channelId.isEmpty())
            s.url = QStringLiteral("https://www.youtube.com/channel/") + s.channelId;
        m_subs.append(s);
    }
    resort();   // load: no view attached yet, plain sort is enough
}

void YtSubscriptions::save() const
{
    const QString path = storePath();
    QDir().mkpath(QFileInfo(path).absolutePath());

    QJsonArray arr;
    for (const Sub &s : m_subs) {
        QJsonObject o;
        o.insert(QStringLiteral("service_id"), 0);
        o.insert(QStringLiteral("channel_id"), s.channelId);
        o.insert(QStringLiteral("name"), s.name);
        o.insert(QStringLiteral("avatar"), s.avatar);
        o.insert(QStringLiteral("url"), s.url);
        o.insert(QStringLiteral("last_seen"), double(s.lastSeen));
        arr.append(o);
    }
    QJsonObject root;
    root.insert(QStringLiteral("app_version"), QStringLiteral("RooTheater"));
    root.insert(QStringLiteral("app_version_int"), 0);
    root.insert(QStringLiteral("subscriptions"), arr);

    QFile f(path);
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        f.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
        f.close();
    }
}
