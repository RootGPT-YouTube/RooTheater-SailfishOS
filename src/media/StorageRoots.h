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

#ifndef STORAGEROOTS_H
#define STORAGEROOTS_H

#include <QObject>
#include <QString>
#include <QStringList>

// StorageRoots discovers, at construction, the gallery's three storage roots on
// this device: internal memory (the user home), the Android App Support shared
// storage (~/android_storage), and any mounted SD cards (/run/media/<user>/*).
// Roots that don't exist come back empty / as an empty list; the UI still shows
// the category but opens to an empty state.
class StorageRoots : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString internalRoot READ internalRoot CONSTANT)
    Q_PROPERTY(QString androidRoot READ androidRoot CONSTANT)
    Q_PROPERTY(QStringList sdcardRoots READ sdcardRoots CONSTANT)
public:
    explicit StorageRoots(QObject *parent = nullptr);

    QString internalRoot() const { return m_internal; }
    QString androidRoot() const { return m_android; }
    QStringList sdcardRoots() const { return m_sdcards; }

private:
    QString m_internal;
    QString m_android;
    QStringList m_sdcards;
};

#endif // STORAGEROOTS_H
