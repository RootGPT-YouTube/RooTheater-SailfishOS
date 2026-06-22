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

#include "FileOperations.h"

#include <QFile>
#include <QUrl>
#include <QDir>
#include <QFileInfo>

namespace {
QString toLocalPath(const QString &path)
{
    if (path.startsWith(QLatin1String("file://")))
        return QUrl(path).toLocalFile();
    return path;
}
}

FileOperations::FileOperations(QObject *parent)
    : QObject(parent)
{
}

bool FileOperations::remove(const QString &path)
{
    return QFile::remove(toLocalPath(path));
}

int FileOperations::removeList(const QStringList &paths)
{
    int removed = 0;
    for (const QString &p : paths) {
        if (QFile::remove(toLocalPath(p)))
            ++removed;
    }
    return removed;
}

bool FileOperations::writeTextFile(const QString &path, const QString &contents)
{
    const QString local = toLocalPath(path);
    QDir().mkpath(QFileInfo(local).absolutePath());
    QFile f(local);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    const QByteArray data = contents.toUtf8();
    const bool ok = f.write(data) == data.size();
    f.close();
    return ok;
}

QString FileOperations::readTextFile(const QString &path)
{
    QFile f(toLocalPath(path));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return QString();
    const QString contents = QString::fromUtf8(f.readAll());
    f.close();
    return contents;
}
