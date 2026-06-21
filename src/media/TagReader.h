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

#ifndef TAGREADER_H
#define TAGREADER_H

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QFutureWatcher>

// QML-instantiable async metadata reader for a single media file. Setting
// filePath kicks off MediaProbe::metadata() on a worker thread and exposes the
// result via `tags` (plus title/artist/album conveniences) when `ready`. Each
// audio delegate in the gallery owns one so titles/covers load lazily as the
// grid scrolls without blocking the GUI thread; the tags view (single-file
// "View tags") reuses the same map.
class TagReader : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString filePath READ filePath WRITE setFilePath NOTIFY filePathChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY tagsChanged)
    Q_PROPERTY(QVariantMap tags READ tags NOTIFY tagsChanged)
    Q_PROPERTY(QString title READ title NOTIFY tagsChanged)
    Q_PROPERTY(QString artist READ artist NOTIFY tagsChanged)
    Q_PROPERTY(QString album READ album NOTIFY tagsChanged)

public:
    explicit TagReader(QObject *parent = nullptr);

    QString filePath() const { return m_filePath; }
    void setFilePath(const QString &path);

    bool ready() const { return m_ready; }
    QVariantMap tags() const { return m_tags; }
    QString title() const { return m_tags.value(QStringLiteral("title")).toString(); }
    QString artist() const { return m_tags.value(QStringLiteral("artist")).toString(); }
    QString album() const { return m_tags.value(QStringLiteral("album")).toString(); }

signals:
    void filePathChanged();
    void tagsChanged();

private slots:
    void onFinished();

private:
    QString m_filePath;
    bool m_ready = false;
    QVariantMap m_tags;
    QFutureWatcher<QVariantMap> m_watcher;
};

#endif // TAGREADER_H
