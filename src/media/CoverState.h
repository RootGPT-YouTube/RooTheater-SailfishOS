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

#ifndef COVERSTATE_H
#define COVERSTATE_H

#include <QObject>
#include <QString>

// Shared playback state bridge between the active page and the app cover (which
// lives in a separate component and can't reach page ids). The viewer/player
// write the current mode/title/preview here; the cover reads them and routes its
// CoverAction taps back through requestPlayPause()/requestNext().
class CoverState : public QObject
{
    Q_OBJECT
    // "none" (no file), "image" (show preview), "media" (audio/video: title + controls)
    Q_PROPERTY(QString mode READ mode WRITE setMode NOTIFY changed)
    Q_PROPERTY(QString title READ title WRITE setTitle NOTIFY changed)
    Q_PROPERTY(QString subtitle READ subtitle WRITE setSubtitle NOTIFY changed)
    Q_PROPERTY(QString imagePath READ imagePath WRITE setImagePath NOTIFY changed)
    // Embedded cover art for the current track (image://rtcover/… token), shown on
    // the media cover when present; empty falls back to the app icon.
    Q_PROPERTY(QString coverArt READ coverArt WRITE setCoverArt NOTIFY changed)
    Q_PROPERTY(bool playing READ playing WRITE setPlaying NOTIFY changed)
public:
    explicit CoverState(QObject *parent = nullptr) : QObject(parent) {}

    QString mode() const { return m_mode; }
    QString title() const { return m_title; }
    QString subtitle() const { return m_subtitle; }
    QString imagePath() const { return m_imagePath; }
    QString coverArt() const { return m_coverArt; }
    bool playing() const { return m_playing; }

    void setMode(const QString &v) { if (m_mode != v) { m_mode = v; emit changed(); } }
    void setTitle(const QString &v) { if (m_title != v) { m_title = v; emit changed(); } }
    void setSubtitle(const QString &v) { if (m_subtitle != v) { m_subtitle = v; emit changed(); } }
    void setImagePath(const QString &v) { if (m_imagePath != v) { m_imagePath = v; emit changed(); } }
    void setCoverArt(const QString &v) { if (m_coverArt != v) { m_coverArt = v; emit changed(); } }
    void setPlaying(bool v) { if (m_playing != v) { m_playing = v; emit changed(); } }

    Q_INVOKABLE void clear()
    {
        setMode(QStringLiteral("none"));
        setTitle(QString());
        setSubtitle(QString());
        setImagePath(QString());
        setCoverArt(QString());
        setPlaying(false);
    }

    // Cover → active page control requests.
    Q_INVOKABLE void requestPlayPause() { emit playPauseRequested(); }
    Q_INVOKABLE void requestNext() { emit nextRequested(); }

signals:
    void changed();
    void playPauseRequested();
    void nextRequested();

private:
    QString m_mode = QStringLiteral("none");
    QString m_title;
    QString m_subtitle;
    QString m_imagePath;
    QString m_coverArt;
    bool m_playing = false;
};

#endif // COVERSTATE_H
