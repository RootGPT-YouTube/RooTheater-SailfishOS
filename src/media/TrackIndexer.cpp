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

#include "TrackIndexer.h"
#include "MediaProbe.h"

#include <QtConcurrent/QtConcurrentRun>

TrackIndexer::TrackIndexer(QObject *parent)
    : QObject(parent)
{
    connect(&m_watcher, &QFutureWatcher<QVariantMap>::finished,
            this, &TrackIndexer::onFinished);
}

void TrackIndexer::read(const QStringList &paths)
{
    if (m_busy)
        return;
    m_busy = true;
    emit busyChanged();

    m_watcher.setFuture(QtConcurrent::run([paths]() {
        QVariantMap out;
        for (const QString &p : paths) {
            const QString t = MediaProbe::metadata(p)
                                  .value(QStringLiteral("track")).toString();
            int n = 0;
            if (!t.isEmpty()) {
                bool ok = false;
                const int v = t.section(QLatin1Char('/'), 0, 0).toInt(&ok);
                if (ok)
                    n = v;
            }
            out.insert(p, n);
        }
        return out;
    }));
}

void TrackIndexer::onFinished()
{
    m_busy = false;
    emit busyChanged();
    emit ready(m_watcher.result());
}
