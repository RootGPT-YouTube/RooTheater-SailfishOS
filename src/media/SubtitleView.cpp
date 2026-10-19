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

#include "SubtitleView.h"
#include "MediaProbe.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFontMetricsF>
#include <QLocale>
#include <QPainter>
#include <QPainterPath>
#include <QRegularExpression>
#include <QTextCodec>
#include <QUrl>

#include <atomic>
#include <mutex>
#include <thread>
#include <vector>

extern "C" {
#include <libavformat/avformat.h>
}

// One reading of one subtitle source. Shared between the view and its worker
// thread, which is detached: a network read can block for a while, so the view
// never joins it — it just raises `stop` and lets go of its reference.
struct SubtitleJob {
    struct Cue { qint64 start; qint64 end; QString text; };
    std::mutex mutex;
    std::vector<Cue> cues;            // in arrival order (≈ time order)
    std::atomic<bool> stop{false};
    std::atomic<bool> done{false};
    std::atomic<bool> failed{false};

    void add(qint64 start, qint64 end, const QString &text)
    {
        if (text.isEmpty() || end <= start)
            return;
        std::lock_guard<std::mutex> lk(mutex);
        cues.push_back(Cue{start, end, text});
    }
};

namespace {

// ── text clean-up ────────────────────────────────────────────────────────────

// Bytes of a subtitle file → text. A BOM decides; otherwise UTF-8 if the bytes
// are valid UTF-8, else Windows-1252 (a superset of Latin-1: accented letters
// and the curly quotes of most non-UTF-8 European .srt files).
QString decodeText(const QByteArray &bytes)
{
    if (bytes.startsWith("\xEF\xBB\xBF"))
        return QString::fromUtf8(bytes.mid(3));
    if (bytes.startsWith("\xFF\xFE") || bytes.startsWith("\xFE\xFF"))
        return QTextCodec::codecForName("UTF-16")->toUnicode(bytes);
    QTextCodec::ConverterState state;
    const QString utf8 = QTextCodec::codecForName("UTF-8")->toUnicode(bytes.constData(), bytes.size(), &state);
    if (state.invalidChars == 0)
        return utf8;
    if (QTextCodec *cp = QTextCodec::codecForName("Windows-1252"))
        return cp->toUnicode(bytes);
    return QString::fromLatin1(bytes);
}

// SRT/WebVTT markup (<i>, <font ...>, <c.yellow>, {\an8}) off, lines trimmed.
QString cleanSrt(QString t)
{
    static const QRegularExpression tags(QStringLiteral("<[^>]*>|\\{\\\\[^}]*\\}"));
    t.remove(tags);
    t.replace(QLatin1String("&amp;"), QLatin1String("&"));
    t.replace(QLatin1String("&lt;"), QLatin1String("<"));
    t.replace(QLatin1String("&gt;"), QLatin1String(">"));
    t.replace(QLatin1String("&nbsp;"), QLatin1String(" "));
    QStringList lines = t.split(QLatin1Char('\n'));
    for (QString &l : lines)
        l = l.trimmed();
    lines.removeAll(QString());
    return lines.join(QLatin1Char('\n'));
}

// ASS dialogue text: override blocks off, \N line breaks, \h hard spaces. A
// cue with a drawing ({\p1}) is vector art, not text: dropped.
QString cleanAss(QString t)
{
    if (t.contains(QRegularExpression(QStringLiteral("\\{[^}]*\\\\p[1-9]"))))
        return QString();
    static const QRegularExpression blocks(QStringLiteral("\\{[^}]*\\}"));
    t.remove(blocks);
    t.replace(QLatin1String("\\N"), QLatin1String("\n"));
    t.replace(QLatin1String("\\n"), QLatin1String("\n"));
    t.replace(QLatin1String("\\h"), QLatin1String(" "));
    return cleanSrt(t);
}

// ── external files ───────────────────────────────────────────────────────────

qint64 hmsToMs(const QString &h, const QString &m, const QString &s, const QString &frac)
{
    // frac is milliseconds in SRT/VTT ("250") and centiseconds in ASS ("25").
    QString f = frac.left(3);
    while (f.length() < 3)
        f += QLatin1Char('0');
    return ((h.toLongLong() * 60 + m.toLongLong()) * 60 + s.toLongLong()) * 1000 + f.toLongLong();
}

void parseSrtOrVtt(const QString &text, SubtitleJob *job)
{
    // 00:01:02,500 --> 00:01:04,000 (SRT) or 01:02.500 --> 01:04.000 (VTT, hours
    // optional), possibly followed by VTT cue settings.
    static const QRegularExpression timing(QStringLiteral(
        "(?:(\\d+):)?(\\d{1,2}):(\\d{1,2})[,.](\\d{1,3})\\s*-->\\s*"
        "(?:(\\d+):)?(\\d{1,2}):(\\d{1,2})[,.](\\d{1,3})"));
    const QStringList lines = text.split(QLatin1Char('\n'));
    for (int i = 0; i < lines.size() && !job->stop; ++i) {
        const QRegularExpressionMatch m = timing.match(lines.at(i));
        if (!m.hasMatch())
            continue;
        const qint64 start = hmsToMs(m.captured(1), m.captured(2), m.captured(3), m.captured(4));
        const qint64 end = hmsToMs(m.captured(5), m.captured(6), m.captured(7), m.captured(8));
        QStringList body;
        while (i + 1 < lines.size() && !lines.at(i + 1).trimmed().isEmpty()
               && !timing.match(lines.at(i + 1)).hasMatch())
            body << lines.at(++i);
        job->add(start, end, cleanSrt(body.join(QLatin1Char('\n'))));
    }
}

void parseAss(const QString &text, SubtitleJob *job)
{
    // [Events] declares its own column order in "Format:"; Text is always last
    // (and may itself contain commas).
    int startCol = 1, endCol = 2, textCol = 9;
    bool inEvents = false;
    static const QRegularExpression time(QStringLiteral("(\\d+):(\\d{1,2}):(\\d{1,2})[.](\\d{1,3})"));
    for (const QString &raw : text.split(QLatin1Char('\n'))) {
        if (job->stop)
            return;
        const QString line = raw.trimmed();
        if (line.startsWith(QLatin1Char('['))) {
            inEvents = line.compare(QLatin1String("[Events]"), Qt::CaseInsensitive) == 0;
            continue;
        }
        if (!inEvents)
            continue;
        if (line.startsWith(QLatin1String("Format:"), Qt::CaseInsensitive)) {
            const QStringList cols = line.mid(7).split(QLatin1Char(','));
            for (int c = 0; c < cols.size(); ++c) {
                const QString n = cols.at(c).trimmed().toLower();
                if (n == QLatin1String("start")) startCol = c;
                else if (n == QLatin1String("end")) endCol = c;
                else if (n == QLatin1String("text")) textCol = c;
            }
            continue;
        }
        if (!line.startsWith(QLatin1String("Dialogue:"), Qt::CaseInsensitive))
            continue;
        const QString rest = line.mid(9);
        // split into textCol fields + the remainder (the text)
        QStringList f;
        int from = 0;
        for (int c = 0; c < textCol; ++c) {
            const int comma = rest.indexOf(QLatin1Char(','), from);
            if (comma < 0) break;
            f << rest.mid(from, comma - from).trimmed();
            from = comma + 1;
        }
        if (f.size() < textCol)
            continue;
        const QRegularExpressionMatch s = time.match(f.value(startCol));
        const QRegularExpressionMatch e = time.match(f.value(endCol));
        if (!s.hasMatch() || !e.hasMatch())
            continue;
        job->add(hmsToMs(s.captured(1), s.captured(2), s.captured(3), s.captured(4)),
                 hmsToMs(e.captured(1), e.captured(2), e.captured(3), e.captured(4)),
                 cleanAss(rest.mid(from)));
    }
}

void readFile(const QString &path, SubtitleJob *job)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly) || f.size() > 16 * 1024 * 1024) {
        job->failed = true;
        return;
    }
    QString text = decodeText(f.readAll());
    text.replace(QLatin1String("\r\n"), QLatin1String("\n"));
    text.replace(QLatin1Char('\r'), QLatin1Char('\n'));
    if (text.contains(QLatin1String("[Script Info]"), Qt::CaseInsensitive)
        || text.contains(QLatin1String("\nDialogue:")))
        parseAss(text, job);
    else
        parseSrtOrVtt(text, job);
    if (job->cues.empty())
        job->failed = true;
}

// ── embedded tracks ──────────────────────────────────────────────────────────

int interruptCb(void *opaque)
{
    return static_cast<std::atomic<bool> *>(opaque)->load() ? 1 : 0;
}

void readStream(const QString &url, int streamIndex, SubtitleJob *job)
{
    const QString path = QUrl(url).isLocalFile() ? QUrl(url).toLocalFile() : url;
    AVFormatContext *fmt = avformat_alloc_context();
    if (!fmt) { job->failed = true; return; }
    fmt->interrupt_callback.callback = &interruptCb;
    fmt->interrupt_callback.opaque = &job->stop;
    AVDictionary *opts = nullptr;
    MediaProbe::applyNetworkOptions(&opts);
    const int rc = avformat_open_input(&fmt, path.toUtf8().constData(), nullptr, &opts);
    av_dict_free(&opts);
    if (rc < 0) { job->failed = true; return; }   // fmt freed by avformat_open_input
    if (streamIndex < 0 || streamIndex >= int(fmt->nb_streams)) {
        avformat_close_input(&fmt);
        job->failed = true;
        return;
    }
    // Only our track: the demuxer then skips the audio/video payload instead of
    // handing it over (MP4 seeks past it; Matroska still reads the clusters).
    for (unsigned i = 0; i < fmt->nb_streams; ++i)
        fmt->streams[i]->discard = int(i) == streamIndex ? AVDISCARD_DEFAULT : AVDISCARD_ALL;
    AVStream *st = fmt->streams[streamIndex];
    const AVCodecID codec = st->codecpar->codec_id;
    const AVRational ms = {1, 1000};

    AVPacket *pkt = av_packet_alloc();
    while (!job->stop && av_read_frame(fmt, pkt) >= 0) {
        if (pkt->stream_index == streamIndex && pkt->size > 0 && pkt->pts != AV_NOPTS_VALUE) {
            const qint64 start = av_rescale_q(pkt->pts, st->time_base, ms);
            const qint64 dur = pkt->duration > 0 ? av_rescale_q(pkt->duration, st->time_base, ms) : 4000;
            QByteArray data(reinterpret_cast<const char *>(pkt->data), pkt->size);
            QString t;
            if (codec == AV_CODEC_ID_MOV_TEXT) {
                // tx3g: 16-bit big-endian length, the UTF-8 text, then style boxes
                const int len = data.size() >= 2 ? (uchar(data[0]) << 8 | uchar(data[1])) : 0;
                t = cleanSrt(QString::fromUtf8(data.mid(2, len)));
            } else if (codec == AV_CODEC_ID_ASS || codec == AV_CODEC_ID_SSA) {
                // Matroska ASS block: ReadOrder,Layer,Style,Name,MarginL,MarginR,
                // MarginV,Effect,Text — the text follows the 8th comma
                const QString line = QString::fromUtf8(data);
                int from = 0;
                for (int c = 0; c < 8 && from >= 0; ++c) {
                    const int comma = line.indexOf(QLatin1Char(','), from);
                    from = comma < 0 ? -1 : comma + 1;
                }
                if (from > 0)
                    t = cleanAss(line.mid(from));
            } else {
                t = cleanSrt(QString::fromUtf8(data).replace(QLatin1String("\r\n"), QLatin1String("\n")));
            }
            job->add(start, start + dur, t);
        }
        av_packet_unref(pkt);
    }
    av_packet_free(&pkt);
    avformat_close_input(&fmt);
}

} // namespace

// ── SubtitleView ─────────────────────────────────────────────────────────────

SubtitleView::SubtitleView(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
    m_jobTimer.setInterval(250);
    connect(&m_jobTimer, &QTimer::timeout, this, &SubtitleView::checkJob);
}

SubtitleView::~SubtitleView()
{
    if (m_job)
        m_job->stop = true;
}

void SubtitleView::setFile(const QString &file)
{
    if (m_file == file)
        return;
    m_file = file;
    emit sourceChanged();
    restart();
}

void SubtitleView::setSource(const QString &source)
{
    if (m_source == source)
        return;
    m_source = source;
    emit sourceChanged();
    restart();
}

void SubtitleView::setStreamIndex(int index)
{
    if (m_streamIndex == index)
        return;
    m_streamIndex = index;
    emit sourceChanged();
    restart();
}

void SubtitleView::setPosition(qlonglong ms)
{
    if (m_position == ms)
        return;
    m_position = ms;
    emit positionChanged();
    refreshText();
}

void SubtitleView::setFontPixelSize(qreal px)
{
    if (qFuzzyCompare(m_fontPixelSize, px))
        return;
    m_fontPixelSize = px;
    emit fontPixelSizeChanged();
    update();
}

int SubtitleView::cueCount() const
{
    if (!m_job)
        return 0;
    std::lock_guard<std::mutex> lk(m_job->mutex);
    return int(m_job->cues.size());
}

bool SubtitleView::failed() const
{
    return m_job && m_job->done && m_job->failed;
}

void SubtitleView::restart()
{
    // file + source + streamIndex usually change together from QML: read once.
    if (m_restartPending)
        return;
    m_restartPending = true;
    QTimer::singleShot(0, this, [this]() {
        m_restartPending = false;
        if (m_job)
            m_job->stop = true;
        m_job.reset();

        const QString file = m_file;
        const QString source = m_source;
        const int stream = m_streamIndex;
        if (!file.isEmpty() || (!source.isEmpty() && stream >= 0)) {
            m_job = std::make_shared<SubtitleJob>();
            std::shared_ptr<SubtitleJob> job = m_job;
            std::thread([job, file, source, stream]() {
                if (!file.isEmpty())
                    readFile(QUrl(file).isLocalFile() ? QUrl(file).toLocalFile() : file, job.get());
                else
                    readStream(source, stream, job.get());
                job->done = true;
            }).detach();
            m_jobTimer.start();
        } else {
            m_jobTimer.stop();
        }
        m_loading = m_job != nullptr;
        emit loadingChanged();
        refreshText();
    });
}

void SubtitleView::checkJob()
{
    // New cues may cover the playhead already; and tell QML when reading ends.
    refreshText();
    if (!m_job || m_job->done) {
        m_jobTimer.stop();
        m_loading = false;
    }
    emit loadingChanged();
}

void SubtitleView::refreshText()
{
    QStringList now;
    if (m_job) {
        std::lock_guard<std::mutex> lk(m_job->mutex);
        for (const SubtitleJob::Cue &c : m_job->cues)
            if (c.start <= m_position && m_position < c.end && !now.contains(c.text))
                now << c.text;
    }
    const QString t = now.join(QLatin1Char('\n'));
    if (t == m_text)
        return;
    m_text = t;
    emit textChanged();
    update();
}

void SubtitleView::paint(QPainter *painter)
{
    if (m_text.isEmpty())
        return;
    QFont font = painter->font();
    font.setPixelSize(qMax(8, qRound(m_fontPixelSize)));
    font.setWeight(QFont::DemiBold);
    const QFontMetricsF fm(font);
    const qreal maxW = width() * 0.92;

    // Word-wrap each cue line to the item's width.
    QStringList lines;
    for (const QString &para : m_text.split(QLatin1Char('\n'))) {
        QString cur;
        for (const QString &word : para.split(QLatin1Char(' '), QString::SkipEmptyParts)) {
            const QString next = cur.isEmpty() ? word : cur + QLatin1Char(' ') + word;
            if (!cur.isEmpty() && fm.width(next) > maxW) {
                lines << cur;
                cur = word;
            } else {
                cur = next;
            }
        }
        if (!cur.isEmpty())
            lines << cur;
    }

    // Bottom-up from the item's bottom edge: an outlined path reads on any
    // picture, light or dark.
    QPainterPath path;
    const qreal lineH = fm.lineSpacing();
    qreal baseline = height() - fm.descent();
    for (int i = lines.size() - 1; i >= 0; --i) {
        const qreal w = fm.width(lines.at(i));
        path.addText((width() - w) / 2, baseline, font, lines.at(i));
        baseline -= lineH;
    }
    painter->setRenderHint(QPainter::Antialiasing);
    painter->strokePath(path, QPen(QColor(0, 0, 0, 220), qMax(2.0, font.pixelSize() / 7.0),
                                   Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
    painter->fillPath(path, Qt::white);
}

QString SubtitleView::findSidecar(const QString &mediaPath)
{
    const QString local = QUrl(mediaPath).isLocalFile() ? QUrl(mediaPath).toLocalFile() : mediaPath;
    if (local.contains(QLatin1String("://")))
        return QString();               // network source: nothing next to it
    const QFileInfo fi(local);
    if (!fi.exists())
        return QString();
    const QString base = fi.completeBaseName();
    QDir dir = fi.dir();
    const QStringList exts = {QStringLiteral("srt"), QStringLiteral("vtt"),
                              QStringLiteral("ass"), QStringLiteral("ssa")};
    // exact "film.srt" first, then "film.<lang>.srt" (UI language preferred)
    for (const QString &e : exts) {
        const QString p = dir.filePath(base + QLatin1Char('.') + e);
        if (QFileInfo::exists(p))
            return p;
    }
    const QString lang = QLocale().name().left(2);
    QStringList filters;
    for (const QString &e : exts)
        filters << base + QStringLiteral(".*.") + e;
    const QStringList found = dir.entryList(filters, QDir::Files, QDir::Name);
    for (const QString &n : found)
        if (n.mid(base.length() + 1).startsWith(lang + QLatin1Char('.')))
            return dir.filePath(n);
    return found.isEmpty() ? QString() : dir.filePath(found.first());
}
