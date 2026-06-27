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

#ifndef OPENHANDLER_H
#define OPENHANDLER_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QVariantList>

// Implements the freedesktop org.freedesktop.Application D-Bus interface so that
// SailfishOS can register RooTheater as a MIME handler and hand it files to open
// ("Open with…" / default app). The bus name + object path are derived from the
// .desktop X-Sailjail OrganizationName/ApplicationName; declaring ExecDBus there
// makes Sailjail auto-generate the service file and grant us that bus name.
//
// Also stores a path passed on the command line at launch (Exec … %U). The QML
// root listens to openRequested()/pendingUrl and routes to the viewer or player.
class OpenHandler : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Application")
    Q_PROPERTY(QString pendingUrl READ pendingUrl NOTIFY openRequested)
public:
    explicit OpenHandler(QObject *parent = nullptr);

    QString pendingUrl() const { return m_pendingUrl; }
    // Seed a path from argv at startup (plain path or file:// URL).
    void setInitialPath(const QString &path);

public slots:
    // ── org.freedesktop.Application ──────────────────────────────────────────
    void Activate(const QVariantMap &platformData);
    void Open(const QStringList &uris, const QVariantMap &platformData);
    void ActivateAction(const QString &actionName, const QVariantList &parameter,
                        const QVariantMap &platformData);

    // Single-argument open used by the Sailfish content-action route (the
    // NoDisplay "open-url" .desktop with X-Maemo-Service/Object-Path/Method).
    // Exported on the same object, so the .desktop's X-Maemo-Method names it
    // under the org.freedesktop.Application interface.
    void openUrl(const QString &url);

signals:
    void openRequested(const QString &path);   // a local file to open
    void activated();                          // bare activation (no file)

private:
    void handle(const QString &uri);
    QString m_pendingUrl;
};

#endif // OPENHANDLER_H
