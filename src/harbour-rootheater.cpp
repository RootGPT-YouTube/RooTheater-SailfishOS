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

#ifdef QT_QML_DEBUG
#include <QtQuick>
#endif

#include <sailfishapp.h>
#include <QScopedPointer>
#include <QGuiApplication>
#include <QQuickView>
#include <QQmlContext>

#ifndef APP_VERSION
#define APP_VERSION "0.0.0"
#endif

int main(int argc, char *argv[])
{
    QScopedPointer<QGuiApplication> app(SailfishApp::application(argc, argv));
    app->setApplicationName("harbour-rootheater");
    app->setApplicationVersion(APP_VERSION);

    QScopedPointer<QQuickView> view(SailfishApp::createView());

    // Exposed to QML (AboutPage); single source of truth is RT_APP_VERSION in the .pro.
    view->rootContext()->setContextProperty("appVersion", QStringLiteral(APP_VERSION));

    view->setSource(SailfishApp::pathTo("qml/harbour-rootheater.qml"));
    view->show();

    return app->exec();
}
