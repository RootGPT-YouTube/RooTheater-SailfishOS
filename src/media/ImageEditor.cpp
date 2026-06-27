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

#include "ImageEditor.h"

#include <QImage>
#include <QImageReader>
#include <QPainter>
#include <QPainterPath>
#include <QPen>
#include <QColor>
#include <QPointF>
#include <QVector>
#include <QFile>
#include <QFileInfo>
#include <QUrl>
#include <QTransform>
#include <QtMath>

namespace {
QString toLocalPath(const QString &path)
{
    if (path.startsWith(QLatin1String("file://")))
        return QUrl(path).toLocalFile();
    return path;
}

// Pull a normalised point list out of an annotation map, scaled to image pixels.
QVector<QPointF> readPoints(const QVariantMap &a, int w, int h)
{
    QVector<QPointF> out;
    const QVariantList pts = a.value(QStringLiteral("points")).toList();
    out.reserve(pts.size());
    for (const QVariant &pv : pts) {
        const QVariantMap m = pv.toMap();
        out.append(QPointF(m.value(QStringLiteral("x")).toReal() * w,
                           m.value(QStringLiteral("y")).toReal() * h));
    }
    return out;
}
}

ImageEditor::ImageEditor(QObject *parent)
    : QObject(parent)
{
}

QString ImageEditor::save(const QString &srcPath,
                          const QRectF &crop,
                          const QVariantList &annotations,
                          int rotation)
{
    const QString path = toLocalPath(srcPath);

    QImageReader reader(path);
    reader.setAutoTransform(true);   // bake EXIF orientation in, like the viewer
    QImage img = reader.read();
    if (img.isNull()) {
        emit error(tr("Could not open image"));
        return QString();
    }
    if (img.format() != QImage::Format_ARGB32
            && img.format() != QImage::Format_RGB32)
        img = img.convertToFormat(QImage::Format_ARGB32);

    // Rotate first, so the crop/annotation coordinates (captured against the
    // rotated preview) map straight onto the pixels below.
    const int rot = ((rotation % 360) + 360) % 360;
    if (rot != 0) {
        QTransform t;
        t.rotate(rot);
        img = img.transformed(t, Qt::SmoothTransformation);
    }

    const int W = img.width();
    const int H = img.height();

    // ── Draw annotations onto the full-resolution image ──────────────────────
    {
        QPainter p(&img);
        p.setRenderHint(QPainter::Antialiasing, true);
        for (const QVariant &av : annotations) {
            const QVariantMap a = av.toMap();
            const QString type = a.value(QStringLiteral("type")).toString();
            const QColor col(a.value(QStringLiteral("color")).toString());
            const qreal penW = qMax<qreal>(1.0,
                                a.value(QStringLiteral("width")).toReal() * W);
            QPen pen(col, penW, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
            p.setPen(pen);
            p.setBrush(Qt::NoBrush);

            const QVector<QPointF> pp = readPoints(a, W, H);
            if (pp.isEmpty())
                continue;

            if (type == QLatin1String("free")) {
                if (pp.size() == 1) {
                    p.drawPoint(pp.first());
                } else {
                    QPainterPath path;
                    path.moveTo(pp.first());
                    for (int i = 1; i < pp.size(); ++i)
                        path.lineTo(pp.at(i));
                    p.drawPath(path);
                }
            } else if (type == QLatin1String("circle")) {
                if (pp.size() >= 2)
                    p.drawEllipse(QRectF(pp.at(0), pp.at(1)).normalized());
            } else if (type == QLatin1String("arrow")) {
                if (pp.size() >= 2) {
                    const QPointF a0 = pp.at(0);
                    const QPointF a1 = pp.at(1);
                    p.drawLine(a0, a1);
                    // Two short barbs at the tip form the arrowhead.
                    const qreal head = qMax<qreal>(penW * 4.0, W * 0.018);
                    const double ang = std::atan2(a1.y() - a0.y(),
                                                  a1.x() - a0.x());
                    const double spread = M_PI / 7.0;
                    p.drawLine(a1, QPointF(a1.x() - head * std::cos(ang - spread),
                                           a1.y() - head * std::sin(ang - spread)));
                    p.drawLine(a1, QPointF(a1.x() - head * std::cos(ang + spread),
                                           a1.y() - head * std::sin(ang + spread)));
                }
            }
        }
    }

    // ── Apply the crop (skip when it's effectively the whole image) ───────────
    if (crop.isValid()) {
        QRect cr(qRound(crop.x() * W), qRound(crop.y() * H),
                 qRound(crop.width() * W), qRound(crop.height() * H));
        cr = cr.intersected(img.rect());
        if (cr.width() > 0 && cr.height() > 0 && cr != img.rect())
            img = img.copy(cr);
    }

    // ── Pick a non-clobbering destination next to the original ────────────────
    const QFileInfo fi(path);
    QString ext = fi.suffix();
    if (ext.isEmpty())
        ext = QStringLiteral("png");
    const QString dir = fi.absolutePath();
    const QString base = fi.completeBaseName();
    QString dest = dir + QLatin1Char('/') + base + QStringLiteral("_edit.") + ext;
    for (int n = 2; QFile::exists(dest); ++n)
        dest = dir + QLatin1Char('/') + base + QStringLiteral("_edit_")
               + QString::number(n) + QLatin1Char('.') + ext;

    const QString lower = ext.toLower();
    bool ok;
    if (lower == QLatin1String("jpg") || lower == QLatin1String("jpeg"))
        ok = img.convertToFormat(QImage::Format_RGB32).save(dest, "JPG", 92);
    else
        ok = img.save(dest);

    if (!ok) {
        emit error(tr("Could not save image"));
        return QString();
    }
    emit saved(dest);
    return dest;
}
