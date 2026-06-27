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

#include "OpenHandler.h"

#include <QUrl>

namespace {
QString toLocalPath(const QString &uri)
{
    if (uri.startsWith(QLatin1String("file://")))
        return QUrl(uri).toLocalFile();
    return uri;
}
}

OpenHandler::OpenHandler(QObject *parent)
    : QObject(parent)
{
}

void OpenHandler::setInitialPath(const QString &path)
{
    if (!path.isEmpty())
        m_pendingUrl = toLocalPath(path);
}

void OpenHandler::Activate(const QVariantMap &)
{
    emit activated();
}

void OpenHandler::Open(const QStringList &uris, const QVariantMap &)
{
    if (uris.isEmpty()) {
        emit activated();
        return;
    }
    handle(uris.first());
}

void OpenHandler::ActivateAction(const QString &, const QVariantList &, const QVariantMap &)
{
    // No app-specific actions are exported.
}

void OpenHandler::openUrl(const QString &url)
{
    handle(url);
}

void OpenHandler::handle(const QString &uri)
{
    const QString p = toLocalPath(uri);
    if (p.isEmpty())
        return;
    m_pendingUrl = p;
    emit openRequested(p);
}
