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

#ifndef TRACKINDEXER_H
#define TRACKINDEXER_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QFutureWatcher>

// Batch reader for audio track numbers. Given a list of files it reads each
// one's "track" metadata tag off the GUI thread and emits a filePath -> track
// number map, so the gallery can offer a "Sort by Track" order without a
// TagReader per row. Track numbers come back as ints (0 when absent), with any
// "n/total" form reduced to n.
class TrackIndexer : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    explicit TrackIndexer(QObject *parent = nullptr);

    bool busy() const { return m_busy; }

    // Read track numbers for `paths`. Re-entrant calls while busy are ignored.
    Q_INVOKABLE void read(const QStringList &paths);

signals:
    void busyChanged();
    void ready(const QVariantMap &trackByPath);

private slots:
    void onFinished();

private:
    bool m_busy = false;
    QFutureWatcher<QVariantMap> m_watcher;
};

#endif // TRACKINDEXER_H
