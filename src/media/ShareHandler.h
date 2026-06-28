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

#ifndef SHAREHANDLER_H
#define SHAREHANDLER_H

#include <QObject>
#include <QVariantMap>
#include <QString>

// Receiver for SailfishOS' "Share with" (Transfer Engine). A media MIME handler
// declares its share method in the .desktop ([X-Share Method <id>] +
// X-Share-Methods). When the user picks it, sailfish-share's generic
// AppShareMethodPlugin.qml resolves service/path/iface from the method id and
// calls  org.sailfishos.share.share(a{sv})  on  /share/<id>  of our bus name.
// The config dict carries "mimeType", "resources" (the file URIs) and
// "selectedTransferMethodInfo"; we pull the first resource and route it to the
// viewer/player exactly like an "Open with". This is a SEPARATE object/interface
// from OpenHandler (org.freedesktop.Application) — both live on the same bus.
class ShareHandler : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.sailfishos.share")
public:
    explicit ShareHandler(QObject *parent = nullptr);

public slots:
    void share(const QVariantMap &config);

signals:
    void shareRequested(const QString &path);   // a local file to open
};

#endif // SHAREHANDLER_H
