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

#include "StorageRoots.h"

#include <QStandardPaths>
#include <QFileInfo>
#include <QDir>

StorageRoots::StorageRoots(QObject *parent)
    : QObject(parent)
{
    // Internal memory = the user home (e.g. /home/defaultuser).
    m_internal = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);

    // Android App Support shared storage. ~/android_storage is the usual bind
    // mount; fall back to the appsupport media path.
    const QString androidUnderHome = m_internal + QStringLiteral("/android_storage");
    if (QFileInfo::exists(androidUnderHome))
        m_android = androidUnderHome;
    else if (QFileInfo::exists(QStringLiteral("/data/media/0")))
        m_android = QStringLiteral("/data/media/0");

    // SD cards: /run/media/<user>/<uuid>.
    const QString user = QFileInfo(m_internal).fileName(); // "defaultuser"
    QDir media(QStringLiteral("/run/media/") + user);
    if (media.exists()) {
        const QStringList mounts = media.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QString &m : mounts)
            m_sdcards << media.absoluteFilePath(m);
    }
}
