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

#ifndef FILEOPERATIONS_H
#define FILEOPERATIONS_H

#include <QObject>
#include <QString>
#include <QStringList>

// Tiny QML-facing helper for the gallery: QML can't delete files on its own,
// so deletion (single or batch) is routed through here. Paths may arrive as
// plain absolute paths or as file:// URLs; both are accepted.
class FileOperations : public QObject
{
    Q_OBJECT
public:
    explicit FileOperations(QObject *parent = nullptr);

    // Deletes one file. Returns true on success.
    Q_INVOKABLE bool remove(const QString &path);
    // Deletes several files. Returns the number actually removed.
    Q_INVOKABLE int removeList(const QStringList &paths);

    // Writes `contents` (UTF-8) to `path`, creating parent directories as needed
    // and truncating any existing file. Used by the playlist builder to save the
    // generated .m3u8. Returns true on success.
    Q_INVOKABLE bool writeTextFile(const QString &path, const QString &contents);

    // Reads `path` and returns its contents as UTF-8 text (empty string if the
    // file can't be read). Used to load a saved .m3u8 playlist for playback.
    Q_INVOKABLE QString readTextFile(const QString &path);
};

#endif // FILEOPERATIONS_H
