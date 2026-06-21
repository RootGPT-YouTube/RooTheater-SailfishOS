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

#include "TagReader.h"
#include "MediaProbe.h"

#include <QtConcurrent/QtConcurrentRun>

TagReader::TagReader(QObject *parent)
    : QObject(parent)
{
    connect(&m_watcher, &QFutureWatcher<QVariantMap>::finished,
            this, &TagReader::onFinished);
}

void TagReader::setFilePath(const QString &path)
{
    if (m_filePath == path)
        return;
    m_filePath = path;
    emit filePathChanged();

    // Reset, then read the new file's tags off the GUI thread. A pending read for
    // a previous path is simply detached (its result is discarded on finish).
    m_ready = false;
    m_tags.clear();
    emit tagsChanged();

    if (!path.isEmpty())
        m_watcher.setFuture(QtConcurrent::run(&MediaProbe::metadata, path));
}

void TagReader::onFinished()
{
    m_tags = m_watcher.result();
    m_ready = true;
    emit tagsChanged();
}
