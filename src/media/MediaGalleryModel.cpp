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

#include "MediaGalleryModel.h"

#include <QtConcurrent/QtConcurrentRun>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QVariantMap>
#include <QSet>
#include <QMap>
#include <algorithm>

namespace {

// Returns 0=image, 1=video, 2=audio, 3=playlist, -1=not media.
int classify(const QString &ext)
{
    static const QSet<QString> img = {
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "heif", "tiff", "tif"
    };
    static const QSet<QString> vid = {
        "mp4", "m4v", "mkv", "webm", "avi", "mov", "3gp", "3g2", "ts", "mts",
        "m2ts", "mpg", "mpeg", "m2v", "vob", "ogv", "flv", "f4v", "wmv", "asf",
        "rm", "rmvb", "divx", "dv"
    };
    static const QSet<QString> aud = {
        "mp3", "flac", "ogg", "oga", "opus", "m4a", "aac", "wav", "wma", "ape",
        "aiff", "aif", "mka", "ac3", "dts", "amr"
    };
    static const QSet<QString> pls = {
        "m3u", "m3u8"
    };
    if (img.contains(ext)) return 0;
    if (vid.contains(ext)) return 1;
    if (aud.contains(ext)) return 2;
    if (pls.contains(ext)) return 3;
    return -1;
}

const char *typeKey(int t)
{
    switch (t) {
    case 0: return "image";
    case 1: return "video";
    case 2: return "audio";
    case 3: return "playlist";
    default: return "";
    }
}

} // namespace

MediaGalleryModel::MediaGalleryModel(QObject *parent)
    : QAbstractListModel(parent)
{
    connect(&m_watcher, &QFutureWatcher<GalleryScanResult>::finished,
            this, &MediaGalleryModel::onScanFinished);
}

MediaGalleryModel::~MediaGalleryModel()
{
    m_watcher.waitForFinished();
}

int MediaGalleryModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_groups.size();
}

QVariant MediaGalleryModel::data(const QModelIndex &index, int role) const
{
    if (index.row() < 0 || index.row() >= m_groups.size())
        return QVariant();
    const GalleryGroup &g = m_groups.at(index.row());
    switch (role) {
    case TypeKeyRole:    return g.typeKey;
    case FolderNameRole: return g.folderName;
    case FolderPathRole: return g.folderPath;
    case CountRole:      return g.items.size();
    case ItemsRole:      return g.items;
    default:             return QVariant();
    }
}

QHash<int, QByteArray> MediaGalleryModel::roleNames() const
{
    return {
        { TypeKeyRole,    "typeKey" },
        { FolderNameRole, "folderName" },
        { FolderPathRole, "folderPath" },
        { CountRole,      "count" },
        { ItemsRole,      "items" }
    };
}

void MediaGalleryModel::setRootPath(const QString &path)
{
    if (m_rootPath == path)
        return;
    m_rootPath = path;
    emit rootPathChanged();

    if (!m_scanning) {
        m_scanning = true;
        emit scanningChanged();
    }
    m_watcher.setFuture(QtConcurrent::run(&MediaGalleryModel::scan, path));
}

void MediaGalleryModel::refresh()
{
    if (m_rootPath.isEmpty())
        return;
    if (!m_scanning) {
        m_scanning = true;
        emit scanningChanged();
    }
    m_watcher.setFuture(QtConcurrent::run(&MediaGalleryModel::scan, m_rootPath));
}

void MediaGalleryModel::removePaths(const QStringList &paths)
{
    if (paths.isEmpty() || m_groups.isEmpty())
        return;

    QSet<QString> drop;
    for (const QString &p : paths)
        drop.insert(p);

    bool removedGroup = false;
    for (int row = m_groups.size() - 1; row >= 0; --row) {
        GalleryGroup &g = m_groups[row];
        QVariantList kept;
        bool changed = false;
        for (const QVariant &v : g.items) {
            if (drop.contains(v.toMap().value("filePath").toString()))
                changed = true;
            else
                kept.append(v);
        }
        if (!changed)
            continue;

        if (kept.isEmpty()) {
            beginRemoveRows(QModelIndex(), row, row);
            m_groups.removeAt(row);
            endRemoveRows();
            removedGroup = true;
        } else {
            g.items = kept;
            const QModelIndex idx = index(row);
            emit dataChanged(idx, idx, { CountRole, ItemsRole });
        }
    }
    if (removedGroup)
        emit countChanged();

    // Keep the per-folder audio breakdown (the "Folders" view) in sync too.
    bool foldersChanged = false;
    for (int i = m_audioFolders.size() - 1; i >= 0; --i) {
        QVariantMap folder = m_audioFolders.at(i).toMap();
        const QVariantList items = folder.value("items").toList();
        QVariantList kept;
        for (const QVariant &v : items)
            if (!drop.contains(v.toMap().value("filePath").toString()))
                kept.append(v);
        if (kept.size() == items.size())
            continue;
        foldersChanged = true;
        if (kept.isEmpty()) {
            m_audioFolders.removeAt(i);
        } else {
            folder.insert("items", kept);
            m_audioFolders[i] = folder;
        }
    }
    if (foldersChanged)
        emit audioFoldersChanged();
}

void MediaGalleryModel::onScanFinished()
{
    const GalleryScanResult res = m_watcher.result();
    beginResetModel();
    m_groups = res.rows;
    endResetModel();
    m_audioFolders = res.audioFolders;
    emit audioFoldersChanged();

    if (m_scanning) {
        m_scanning = false;
        emit scanningChanged();
    }
    emit countChanged();
}

// Worker thread: walk `root` (skipping hidden dirs, symlinks and the sibling
// Android mount), bucket media by (folder, type), and return one group per
// (folder, type) ordered by type then folder name, items ordered by name.
// Audio is the exception: all audio files collapse into ONE row (the gallery
// shows library categories for it), with the folder split kept separately.
GalleryScanResult MediaGalleryModel::scan(const QString &root)
{
    GalleryScanResult out;
    QVector<GalleryGroup> &result = out.rows;
    if (root.isEmpty() || !QFileInfo::exists(root))
        return out;

    QMimeDatabase db;
    // folderPath -> per-type item lists [image, video, audio]
    QMap<QString, QVector<QVariantList>> byDir;

    QStringList queue;
    queue << root;
    while (!queue.isEmpty()) {
        const QString dirPath = queue.takeFirst();
        QDir dir(dirPath);

        const QFileInfoList files = dir.entryInfoList(QDir::Files | QDir::NoSymLinks);
        for (const QFileInfo &fi : files) {
            const int t = classify(fi.suffix().toLower());
            if (t < 0)
                continue;
            QVector<QVariantList> &buckets = byDir[dirPath];
            if (buckets.isEmpty())
                buckets.resize(4);
            QVariantMap item;
            item.insert("filePath", fi.absoluteFilePath());
            item.insert("fileName", fi.fileName());
            item.insert("mimeType",
                        db.mimeTypeForFile(fi, QMimeDatabase::MatchExtension).name());
            // Carried so the folder grid can sort by size / date without re-stat'ing.
            item.insert("size", static_cast<qlonglong>(fi.size()));
            item.insert("modified", fi.lastModified().toMSecsSinceEpoch());
            buckets[t].append(item);
        }

        const QFileInfoList subdirs =
            dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::NoSymLinks);
        for (const QFileInfo &di : subdirs) {
            const QString name = di.fileName();
            if (name.startsWith(QLatin1Char('.')) || name == QLatin1String("android_storage"))
                continue;
            queue << di.absoluteFilePath();
        }
    }

    auto byName = [](const QVariant &a, const QVariant &b) {
        return a.toMap().value("fileName").toString().toLower()
             < b.toMap().value("fileName").toString().toLower();
    };

    QVariantList audioAll;
    for (auto it = byDir.begin(); it != byDir.end(); ++it) {
        const QString &path = it.key();
        QVector<QVariantList> &buckets = it.value();
        for (int t = 0; t < 4; ++t) {
            if (buckets[t].isEmpty())
                continue;
            std::sort(buckets[t].begin(), buckets[t].end(), byName);
            QString folderName = QFileInfo(path).fileName();
            if (folderName.isEmpty())
                folderName = path;
            if (t == 2) {
                QVariantMap folder;
                folder.insert("folderName", folderName);
                folder.insert("folderPath", path);
                folder.insert("items", buckets[t]);
                out.audioFolders.append(folder);
                audioAll += buckets[t];
                continue;
            }
            GalleryGroup g;
            g.type = t;
            g.typeKey = QString::fromLatin1(typeKey(t));
            g.folderPath = path;
            g.folderName = folderName;
            g.items = buckets[t];
            result.append(g);
        }
    }

    // Single audio row carrying every audio file of this storage; the gallery
    // renders it as the songs/albums/artists/folders category block.
    if (!audioAll.isEmpty()) {
        GalleryGroup g;
        g.type = 2;
        g.typeKey = QString::fromLatin1(typeKey(2));
        g.folderPath = root;
        g.folderName = QFileInfo(root).fileName();
        g.items = audioAll;
        result.append(g);
    }

    std::sort(out.audioFolders.begin(), out.audioFolders.end(),
              [](const QVariant &a, const QVariant &b) {
                  return a.toMap().value("folderName").toString()
                             .compare(b.toMap().value("folderName").toString(),
                                      Qt::CaseInsensitive) < 0;
              });

    // Order by type (images, videos, audio, playlists), then folder name.
    std::sort(result.begin(), result.end(),
              [](const GalleryGroup &a, const GalleryGroup &b) {
                  if (a.type != b.type)
                      return a.type < b.type;
                  return a.folderName.compare(b.folderName, Qt::CaseInsensitive) < 0;
              });
    return out;
}
