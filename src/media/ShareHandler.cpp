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

#include "ShareHandler.h"

#include <QUrl>
#include <QStringList>
#include <QVariantList>
#include <QDBusArgument>
#include <QDBusVariant>
#include <QMetaType>

namespace {
QString toLocalPath(const QString &uri)
{
    if (uri.startsWith(QLatin1String("file://")))
        return QUrl(uri).toLocalFile();
    return uri;
}

// The "resources" value of the share config is a D-Bus variant that usually
// wraps an array of variants (av), but be liberal and also accept as / a list /
// a bare string. Return the first non-empty entry.
QString firstResource(QVariant v)
{
    if (v.userType() == qMetaTypeId<QDBusVariant>())
        v = v.value<QDBusVariant>().variant();

    if (v.userType() == qMetaTypeId<QDBusArgument>()) {
        // MUST be const, else beginArray()/>> pick the write overloads
        // ("QDBusArgument: write from a read-only object") and extract nothing.
        const QDBusArgument arg = v.value<QDBusArgument>();
        QString first;
        arg.beginArray();
        while (!arg.atEnd() && first.isEmpty()) {
            if (arg.currentType() == QDBusArgument::VariantType) {
                QDBusVariant e;          // resources is av (array of variant)
                arg >> e;
                first = e.variant().toString();
            } else {
                QString s;               // tolerate a plain as (array of string)
                arg >> s;
                first = s;
            }
        }
        arg.endArray();
        return first;
    }
    if (v.userType() == QMetaType::QStringList) {
        const QStringList l = v.toStringList();
        return l.isEmpty() ? QString() : l.first();
    }
    if (v.userType() == QMetaType::QVariantList) {
        const QVariantList l = v.toList();
        return l.isEmpty() ? QString() : l.first().toString();
    }
    return v.toString();
}
}

ShareHandler::ShareHandler(QObject *parent)
    : QObject(parent)
{
}

void ShareHandler::share(const QVariantMap &config)
{
    const QString path = toLocalPath(firstResource(config.value(QStringLiteral("resources"))));
    if (!path.isEmpty())
        emit shareRequested(path);
}
