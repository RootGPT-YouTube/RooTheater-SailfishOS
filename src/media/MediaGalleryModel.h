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

#ifndef MEDIAGALLERYMODEL_H
#define MEDIAGALLERYMODEL_H

#include <QAbstractListModel>
#include <QString>
#include <QVector>
#include <QVariantList>
#include <QFutureWatcher>

// One model row = one (folder × media-type) group: a folder that contains at
// least one item of a given type (image / video / audio / playlist). So a folder
// with both photos and clips yields two rows. Rows are ordered by type (images,
// then videos, then audio, then playlists) and then folder name, so a
// section-by-type list shows "Images / Videos / Audio / Playlists" with the
// matching folders under each.
struct GalleryGroup
{
    int type = 0;          // 0 image, 1 video, 2 audio, 3 playlist
    QString typeKey;       // "image"/"video"/"audio"/"playlist" (QML section + routing)
    QString folderName;
    QString folderPath;
    QVariantList items;    // [{ filePath, fileName, mimeType }, …] (this type only)
};

// MediaGalleryModel scans a storage root (set via rootPath) for image/video/audio
// files and groups them by folder AND type. The scan runs on a worker thread;
// hidden dirs and the sibling Android mount are skipped.
class MediaGalleryModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(QString rootPath READ rootPath WRITE setRootPath NOTIFY rootPathChanged)
    Q_PROPERTY(bool scanning READ scanning NOTIFY scanningChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
public:
    enum Roles {
        TypeKeyRole = Qt::UserRole + 1,
        FolderNameRole,
        FolderPathRole,
        CountRole,
        ItemsRole
    };

    explicit MediaGalleryModel(QObject *parent = nullptr);
    ~MediaGalleryModel() override;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString rootPath() const { return m_rootPath; }
    void setRootPath(const QString &path);
    bool scanning() const { return m_scanning; }
    int count() const { return m_groups.size(); }

    // Drop files (by absolute path) from the cached groups so the gallery stays
    // in sync after a delete inside a folder, without a full re-scan. Groups left
    // empty are removed. Called from QML (FolderContentPage → GalleryPage).
    Q_INVOKABLE void removePaths(const QStringList &paths);

    // Re-scan the current root from scratch. Used after a file appears outside
    // this model's knowledge (e.g. a newly saved playlist).
    Q_INVOKABLE void refresh();

signals:
    void rootPathChanged();
    void scanningChanged();
    void countChanged();

private slots:
    void onScanFinished();

private:
    static QVector<GalleryGroup> scan(const QString &root);

    QString m_rootPath;
    bool m_scanning = false;
    QVector<GalleryGroup> m_groups;
    QFutureWatcher<QVector<GalleryGroup>> m_watcher;
};

#endif // MEDIAGALLERYMODEL_H
