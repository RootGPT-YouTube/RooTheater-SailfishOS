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

#include "DroidCodecBackend.h"
#include "DroidCodec.h"
#include "DroidVideoSink.h"

#include <QUrl>
#include <QThread>
#include <QDebug>

#include <cstring>
#include <cstdlib>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavcodec/bsf.h>
#include <libavutil/mathematics.h>
#include <libavutil/rational.h>
#include <libavutil/channel_layout.h>
#include <libswresample/swresample.h>

#include <pulse/simple.h>
#include <pulse/error.h>

#include <droidmedia.h>
#include <droidmediacodec.h>
}

#include <chrono>

namespace {
// Audio packet-queue depth. Demux blocks when full, so the audio thread's
// real-time pa_simple_write paces the WHOLE pipeline (demux + video) — bounding
// memory and keeping A/V together. ~96 packets ≈ a couple seconds of audio.
const size_t kMaxAudioPackets = 96;

// Monotonic wall clock shared between the audio and video threads (microseconds).
qint64 steadyNowUs()
{
    using namespace std::chrono;
    return duration_cast<microseconds>(steady_clock::now().time_since_epoch()).count();
}
}

namespace {

// ffmpeg codec id → (OMX MIME, Annex-B bitstream-filter name). Only codecs the
// droidmedia HW decoders take; selection already gated by DroidCodec.
struct CodecMap { AVCodecID id; const char *mime; const char *bsf; };
const CodecMap kCodecs[] = {
    { AV_CODEC_ID_H264, "video/avc",  "h264_mp4toannexb" },
    { AV_CODEC_ID_HEVC, "video/hevc", "hevc_mp4toannexb" },
    { AV_CODEC_ID_VP9,  "video/x-vnd.on2.vp9", nullptr },
    { AV_CODEC_ID_VP8,  "video/x-vnd.on2.vp8", nullptr },
    { AV_CODEC_ID_MPEG4, "video/mp4v-es", nullptr },
};
const CodecMap *mapFor(AVCodecID id)
{
    for (const auto &m : kCodecs)
        if (m.id == id) return &m;
    return nullptr;
}

// C thunks for the codec's output DroidMediaBufferQueue (its callback arg types
// can't be forward-declared in the header, so the trampolines live here).
// frame_available returns true: WE took the buffer and are responsible for
// releasing it back to the pool (droid_media_buffer_release).
bool frameAvailableThunk(void *data, DroidMediaBuffer *buffer)
{
    static_cast<DroidCodecBackend *>(data)->onFrameAvailable(buffer);
    return true;
}
bool bufferCreatedThunk(void *, DroidMediaBuffer *) { return true; }
void buffersReleasedThunk(void *) {}

// Buffer ref/unref for droid_media_codec_queue(). droidmedia dereferences this
// callbacks pointer (it does NOT accept null — passing null crashes inside
// libdroidmedia), and may hold the input data past the call, so we hand it an
// owned copy and free it on unref.
void rtBufRef(void *) {}
void rtBufUnref(void *data) { free(data); }

} // namespace

DroidCodecBackend::DroidCodecBackend(QObject *parent)
    : QObject(parent)
{
    // Worker → GUI marshalling for state/position (frames go via frameReady).
    connect(this, &DroidCodecBackend::postState, this,
            &DroidCodecBackend::onPostState, Qt::QueuedConnection);
    connect(this, &DroidCodecBackend::postPosition, this,
            &DroidCodecBackend::onPostPosition, Qt::QueuedConnection);
    connect(this, &DroidCodecBackend::postDuration, this,
            &DroidCodecBackend::onPostDuration, Qt::QueuedConnection);
}

DroidCodecBackend::~DroidCodecBackend()
{
    stop();
}

void DroidCodecBackend::setVideoOutput(VideoSurface *output)
{
    if (m_output == output)
        return;
    if (m_output)
        disconnect(this, &DroidCodecBackend::frameReady, m_output, &VideoSurface::presentFrame);
    m_output = output;
    if (m_output)
        connect(this, &DroidCodecBackend::frameReady,
                m_output, &VideoSurface::presentFrame, Qt::QueuedConnection);
    emit videoOutputChanged();
}

void DroidCodecBackend::setVideoSink(DroidVideoSink *sink)
{
    if (m_sink == sink)
        return;
    m_sink = sink;
    emit videoSinkChanged();
}

void DroidCodecBackend::setLoop(bool on)
{
    if (m_loop.load() == on)
        return;
    m_loop.store(on);
    emit loopChanged();
}

// ── lifecycle ────────────────────────────────────────────────────────────────

void DroidCodecBackend::play(const QString &url)
{
    stop();
    m_url = url;
    m_stop = false;
    m_paused = false;
    m_firstPtsUs = -1;
    m_loopOffsetUs.store(0);
    { std::lock_guard<std::mutex> lk(m_clockMutex); m_clockValid = false; }
    emit postState(Opening);
    m_demuxThread = std::thread([this]() { demuxLoop(); });
}

void DroidCodecBackend::pause()
{
    if (m_state == Playing) {
        m_paused = true;
        emit postState(Paused);
    }
}

void DroidCodecBackend::togglePause()
{
    if (m_state == Playing)
        pause();
    else if (m_state == Paused) {
        m_paused = false;
        // Re-anchor the clock so we don't fast-forward to catch up.
        m_firstPtsUs = -1;
        emit postState(Playing);
    }
}

void DroidCodecBackend::stop()
{
    m_stop = true;
    m_paused = false;
    // Wake the audio thread (it may be blocked on the packet queue) and the demux
    // thread (it may be blocked pushing to a full queue), then join both.
    m_aqNotEmpty.notify_all();
    m_aqNotFull.notify_all();
    if (m_demuxThread.joinable())
        m_demuxThread.join();
    if (m_audioThread.joinable())
        m_audioThread.join();
    // Return the sink's pinned buffers to the pool BEFORE destroying the codec
    // (the buffer queue dies with it), else a later release is use-after-free.
    if (m_sink)
        m_sink->reset();
    teardown();
    if (m_state != Stopped) {
        m_state = Stopped;
        emit stateChanged();
    }
    if (m_output)
        m_output->clear();
}

void DroidCodecBackend::seek(qlonglong ms)
{
    // Robust seek = RESTART the pipeline at the target. Flushing the live OMX
    // decoder fails on this device: it can't reclaim the output buffers the
    // zero-copy sink still holds ("can not return buffer to native window" →
    // the codec errors out and dies). So we tear down and re-open at the seek
    // point, reusing the proven stop()/play() path. Heavier (codec re-init) but
    // reliable; a smoother in-place seek can come once buffer hand-back is solved.
    if (m_state != Playing && m_state != Paused)
        return;
    if (ms < 0)
        ms = 0;
    m_startMs = ms;        // consumed by openInput() of the restarted pipeline
    play(m_url);           // play() calls stop() first (joins threads, teardown)
    m_positionMs = ms;     // optimistic until the first post-seek frame posts
    emit positionChanged();
}

// ── ffmpeg demux + droidmedia decode (worker thread) ─────────────────────────

bool DroidCodecBackend::openInput(const QString &url)
{
    const QString path = QUrl(url).isLocalFile() ? QUrl(url).toLocalFile() : url;
    const QByteArray src = path.toUtf8();

    if (avformat_open_input(&m_fmt, src.constData(), nullptr, nullptr) < 0)
        { qWarning("DroidCodec: avformat_open_input failed"); return false; }
    if (avformat_find_stream_info(m_fmt, nullptr) < 0)
        { qWarning("DroidCodec: find_stream_info failed"); return false; }

    m_videoStream = av_find_best_stream(m_fmt, AVMEDIA_TYPE_VIDEO, -1, -1, nullptr, 0);
    if (m_videoStream < 0)
        { qWarning("DroidCodec: no video stream"); return false; }

    AVStream *st = m_fmt->streams[m_videoStream];
    const CodecMap *cm = mapFor(st->codecpar->codec_id);
    if (!cm)
        { qWarning("DroidCodec: codec %d not mapped", st->codecpar->codec_id); return false; }

    // openInput runs on the worker thread; marshal duration/seekable to the GUI
    // thread so the NOTIFY signals fire there (QML never saw them before, which
    // pinned the seek slider to the end with duration stuck at 0).
    if (m_fmt->duration > 0)
        emit postDuration(m_fmt->duration / (AV_TIME_BASE / 1000));

    // Seek target carried over from seek() (which restarts the pipeline): jump to
    // the keyframe at/just before it before any packet is read or decoded.
    if (m_startMs > 0) {
        av_seek_frame(m_fmt, -1, av_rescale(m_startMs, AV_TIME_BASE, 1000), AVSEEK_FLAG_BACKWARD);
        m_startMs = 0;
    }

    // Bitstream filter → Annex-B (mp4/mkv carry AVCC). VP8/VP9 need none.
    if (cm->bsf) {
        const AVBitStreamFilter *f = av_bsf_get_by_name(cm->bsf);
        if (!f || av_bsf_alloc(f, &m_bsf) < 0)
            { qWarning("DroidCodec: bsf %s alloc failed", cm->bsf); return false; }
        avcodec_parameters_copy(m_bsf->par_in, st->codecpar);
        m_bsf->time_base_in = st->time_base;
        if (av_bsf_init(m_bsf) < 0)
            { qWarning("DroidCodec: bsf init failed"); return false; }
    }
    qInfo("DroidCodec: %s %dx%d mime=%s", cm->bsf ? cm->bsf : "raw",
          st->codecpar->width, st->codecpar->height, cm->mime);

    // droidmedia decoder. codec_data = the (Annex-B, after bsf) SPS/PPS so the
    // OMX decoder is configured even before the first in-band parameter set.
    DroidMediaCodecDecoderMetaData meta;
    std::memset(&meta, 0, sizeof(meta));
    meta.parent.type = cm->mime;
    meta.parent.width = st->codecpar->width;
    meta.parent.height = st->codecpar->height;
    AVRational fr = st->avg_frame_rate;
    meta.parent.fps = (fr.den > 0) ? (fr.num / fr.den) : 30;
    // No NO_MEDIA_BUFFER flag: the decoder outputs gralloc buffers on its
    // DroidMediaBufferQueue (zero-copy v0.3.3), not a linear CPU buffer.
    // meta.parent.flags stays 0 (memset above).

    // codec_data MUST be the container's codec config (avcC/hvcC box), NOT the
    // Annex-B SPS/PPS: droidmedia hands it to stagefright's
    // convertMetaDataToMessage(), which parses it as an avcC box (passing the
    // bsf's Annex-B extradata here fails with "Cannot convertMetaDataToMessage").
    // The decoded *frames* are still fed as Annex-B via the bitstream filter.
    if (st->codecpar->extradata && st->codecpar->extradata_size > 0) {
        meta.codec_data.size = st->codecpar->extradata_size;
        meta.codec_data.data = st->codecpar->extradata;
    }

    if (!droid_media_codec_is_supported(&meta.parent, false))
        { qWarning("DroidCodec: is_supported=false for %s", cm->mime); return false; }

    m_codec = droid_media_codec_create_decoder(&meta);
    if (!m_codec)
        { qWarning("DroidCodec: create_decoder returned null"); return false; }

    DroidMediaCodecCallbacks cb;
    std::memset(&cb, 0, sizeof(cb));
    cb.signal_eos = &DroidCodecBackend::eosCb;
    cb.error = &DroidCodecBackend::errorCb;
    cb.size_changed = &DroidCodecBackend::sizeChangedCb;
    droid_media_codec_set_callbacks(m_codec, &cb, this);

    // Output path: decoded gralloc buffers arrive on the codec's buffer queue.
    m_queue = droid_media_codec_get_buffer_queue(m_codec);
    if (!m_queue)
        { qWarning("DroidCodec: get_buffer_queue returned null"); return false; }
    DroidMediaBufferQueueCallbacks qcb;
    std::memset(&qcb, 0, sizeof(qcb));
    qcb.buffer_created = &bufferCreatedThunk;
    qcb.frame_available = &frameAvailableThunk;
    qcb.buffers_released = &buffersReleasedThunk;
    droid_media_buffer_queue_set_callbacks(m_queue, &qcb, this);

    if (!droid_media_codec_start(m_codec))
        { qWarning("DroidCodec: codec_start failed"); return false; }
    qInfo("DroidCodec: decoder started (buffer-queue output)");

    // Audio is best-effort: a failure here must not stop the (working) video.
    m_hasAudio = openAudio();
    return true;
}

bool DroidCodecBackend::openAudio()
{
    m_audioStream = av_find_best_stream(m_fmt, AVMEDIA_TYPE_AUDIO, -1, -1, nullptr, 0);
    if (m_audioStream < 0)
        { qInfo("DroidCodec: no audio stream"); return false; }

    AVStream *as = m_fmt->streams[m_audioStream];
    const AVCodec *dec = avcodec_find_decoder(as->codecpar->codec_id);
    if (!dec) { qWarning("DroidCodec: no audio decoder for id %d", as->codecpar->codec_id); return false; }
    m_audioCtx = avcodec_alloc_context3(dec);
    if (!m_audioCtx) return false;
    avcodec_parameters_to_context(m_audioCtx, as->codecpar);
    if (avcodec_open2(m_audioCtx, dec, nullptr) < 0)
        { qWarning("DroidCodec: avcodec_open2 (audio) failed"); return false; }

    m_outRate = m_audioCtx->sample_rate > 0 ? m_audioCtx->sample_rate : 48000;
    m_outChannels = m_audioCtx->ch_layout.nb_channels >= 2 ? 2 : 1; // downmix to stereo/mono

    AVChannelLayout outLayout;
    av_channel_layout_default(&outLayout, m_outChannels);
    if (swr_alloc_set_opts2(&m_swr, &outLayout, AV_SAMPLE_FMT_S16, m_outRate,
                            &m_audioCtx->ch_layout, m_audioCtx->sample_fmt,
                            m_audioCtx->sample_rate, 0, nullptr) < 0 || swr_init(m_swr) < 0)
        { qWarning("DroidCodec: swresample init failed"); av_channel_layout_uninit(&outLayout); return false; }
    av_channel_layout_uninit(&outLayout);

    qInfo("DroidCodec: audio %d Hz, %d ch (out S16) — PulseAudio", m_outRate, m_outChannels);
    m_audioThread = std::thread([this]() { audioLoop(); });
    return true;
}

void DroidCodecBackend::demuxLoop()
{
    if (!DroidCodec::initialize() || !openInput(m_url)) {
        emit postState(Error);
        return;
    }
    emit postState(Playing);

    AVStream *st = m_fmt->streams[m_videoStream];
    AVPacket *pkt = av_packet_alloc();
    AVPacket *out = av_packet_alloc();

    auto submit = [&](AVPacket *p) {
        // droidmedia may hold the input data past the call and frees it via the
        // unref callback, so hand it an owned copy (not the AVPacket's buffer).
        void *copy = malloc(static_cast<size_t>(p->size));
        if (!copy)
            return;
        std::memcpy(copy, p->data, static_cast<size_t>(p->size));

        DroidMediaCodecData d;
        std::memset(&d, 0, sizeof(d));
        d.data.data = copy;
        d.data.size = p->size;
        d.ts = ((p->pts != AV_NOPTS_VALUE)
                ? av_rescale_q(p->pts, st->time_base, AVRational{1, 1000000}) : 0)
               + m_loopOffsetUs.load();   // keep fed ts monotonic across loops
        d.sync = (p->flags & AV_PKT_FLAG_KEY) != 0;

        // Non-null callbacks are REQUIRED: droid_media_codec_queue dereferences
        // this pointer (passing null crashes inside libdroidmedia at +0x12c4c).
        DroidMediaBufferCallbacks cb;
        std::memset(&cb, 0, sizeof(cb));
        cb.ref = &rtBufRef;
        cb.unref = &rtBufUnref;   // frees the copy when droidmedia is done
        cb.data = copy;
        droid_media_codec_queue(m_codec, &d, &cb);
    };

    while (!m_stop) {
        if (m_paused) { QThread::msleep(20); continue; }
        if (av_read_frame(m_fmt, pkt) < 0) {
            // EOF. If looping, rewind the demuxer and keep feeding the SAME
            // decoder (no teardown). Bump the timestamp offset by the file
            // duration so fed video+audio ts stay monotonic across loops.
            av_packet_unref(pkt);
            if (m_loop.load() && !m_stop && m_fmt->duration > 0) {
                m_loopOffsetUs.fetch_add(m_fmt->duration);
                av_seek_frame(m_fmt, -1, 0, AVSEEK_FLAG_BACKWARD);
                if (m_bsf) av_bsf_flush(m_bsf);
                continue;
            }
            break;
        }
        if (pkt->stream_index == m_videoStream) {
            if (m_bsf) {
                if (av_bsf_send_packet(m_bsf, pkt) == 0)
                    while (av_bsf_receive_packet(m_bsf, out) == 0) {
                        submit(out);
                        av_packet_unref(out);
                    }
            } else {
                submit(pkt);
            }
        } else if (m_hasAudio && pkt->stream_index == m_audioStream) {
            // Hand a cloned packet to the audio thread, with backpressure: this
            // wait is what paces the demux (and thus the whole pipeline) to the
            // audio thread's real-time output.
            if (AVPacket *clone = av_packet_clone(pkt)) {
                // Same loop offset as the video, in the audio stream's time base,
                // so the audio master clock stays monotonic across loops too.
                const qint64 off = m_loopOffsetUs.load();
                if (off > 0) {
                    const int64_t a = av_rescale_q(off, AVRational{1, 1000000},
                                                   m_fmt->streams[m_audioStream]->time_base);
                    if (clone->pts != AV_NOPTS_VALUE) clone->pts += a;
                    if (clone->dts != AV_NOPTS_VALUE) clone->dts += a;
                }
                std::unique_lock<std::mutex> lk(m_aqMutex);
                m_aqNotFull.wait(lk, [this] { return m_stop || m_aq.size() < kMaxAudioPackets; });
                if (m_stop) { lk.unlock(); av_packet_free(&clone); }
                else { m_aq.push_back(clone); lk.unlock(); m_aqNotEmpty.notify_one(); }
            }
        }
        av_packet_unref(pkt);
    }

    // Tell the audio thread no more packets are coming (EOF sentinel = nullptr).
    if (m_hasAudio) {
        std::lock_guard<std::mutex> lk(m_aqMutex);
        m_aq.push_back(nullptr);
        m_aqNotEmpty.notify_one();
    }

    if (!m_stop) {
        droid_media_codec_drain(m_codec);
        emit postState(Ended);
    }
    av_packet_free(&pkt);
    av_packet_free(&out);
}

void DroidCodecBackend::audioLoop()
{
    AVFrame *frame = av_frame_alloc();
    int maxOutSamples = 0;
    uint8_t *outBuf = nullptr;   // interleaved S16 scratch
    int err = 0;

    auto popPacket = [this](AVPacket **pktOut, bool *eof) -> bool {
        std::unique_lock<std::mutex> lk(m_aqMutex);
        m_aqNotEmpty.wait(lk, [this] { return m_stop || !m_aq.empty(); });
        if (m_stop) return false;
        AVPacket *p = m_aq.front();
        m_aq.pop_front();
        lk.unlock();
        m_aqNotFull.notify_one();
        if (!p) { *eof = true; *pktOut = nullptr; return true; } // EOF sentinel
        *pktOut = p;
        return true;
    };

    AVStream *as = m_fmt->streams[m_audioStream];
    bool eof = false;
    while (!m_stop && !eof) {
        if (m_paused) { QThread::msleep(20); continue; }

        AVPacket *pkt = nullptr;
        if (!popPacket(&pkt, &eof))
            break;
        if (avcodec_send_packet(m_audioCtx, pkt) == 0 || eof) { /* keep draining on eof */ }
        av_packet_free(&pkt);

        while (!m_stop && avcodec_receive_frame(m_audioCtx, frame) == 0) {
            const int outSamples = swr_get_out_samples(m_swr, frame->nb_samples);
            const int needBytes = outSamples * m_outChannels * 2;
            if (outSamples > maxOutSamples) {
                free(outBuf);
                outBuf = static_cast<uint8_t *>(malloc(needBytes));
                maxOutSamples = outSamples;
            }
            if (!outBuf) break;
            const int n = swr_convert(m_swr, &outBuf, outSamples,
                                      const_cast<const uint8_t **>(frame->extended_data),
                                      frame->nb_samples);
            if (n <= 0)
                continue;
            const int bytes = n * m_outChannels * 2;

            // Lazily open the PulseAudio stream now that we know the format.
            if (!m_pa) {
                pa_sample_spec ss;
                ss.format = PA_SAMPLE_S16LE;
                ss.rate = m_outRate;
                ss.channels = m_outChannels;
                m_pa = pa_simple_new(nullptr, "RooTheater", PA_STREAM_PLAYBACK, nullptr,
                                     "playback", &ss, nullptr, nullptr, &err);
                if (!m_pa) { qWarning("DroidCodec: pa_simple_new failed: %s", pa_strerror(err)); m_hasAudio = false; goto done; }
                qInfo("DroidCodec: PulseAudio stream opened");
            }

            // Master clock: timestamp of audio now AUDIBLE = this frame's pts minus
            // whatever is still buffered downstream in PulseAudio.
            if (frame->pts != AV_NOPTS_VALUE) {
                const qint64 ptsUs = av_rescale_q(frame->pts, as->time_base, AVRational{1, 1000000});
                const pa_usec_t lat = pa_simple_get_latency(m_pa, &err);
                setAudioAnchor(qMax<qint64>(0, ptsUs - static_cast<qint64>(lat)));
            }

            if (pa_simple_write(m_pa, outBuf, static_cast<size_t>(bytes), &err) < 0) {
                qWarning("DroidCodec: pa_simple_write failed: %s", pa_strerror(err));
                m_hasAudio = false;
                goto done;
            }
        }
    }

done:
    if (m_pa && !m_stop)
        pa_simple_drain(m_pa, &err);
    free(outBuf);
    av_frame_free(&frame);
}

// ── decoded-frame path (droidmedia decode thread) ────────────────────────────

void DroidCodecBackend::eosCb(void *data)
{
    emit static_cast<DroidCodecBackend *>(data)->postState(Ended);
}

void DroidCodecBackend::errorCb(void *data, int err)
{
    qWarning("DroidCodec: codec error callback err=%d", err);
    emit static_cast<DroidCodecBackend *>(data)->postState(Error);
}

int DroidCodecBackend::sizeChangedCb(void *, int32_t, int32_t)
{
    return 0; // geometry is read per buffer from droid_media_buffer_get_info
}

void DroidCodecBackend::setAudioAnchor(qint64 audibleUs)
{
    std::lock_guard<std::mutex> lk(m_clockMutex);
    m_clockBaseUs = audibleUs;
    m_clockBaseAtUs = steadyNowUs();
    m_clockValid = true;
}

qint64 DroidCodecBackend::masterClockUs()
{
    std::lock_guard<std::mutex> lk(m_clockMutex);
    if (!m_clockValid)
        return -1;
    return m_clockBaseUs + (steadyNowUs() - m_clockBaseAtUs);
}

void DroidCodecBackend::onFrameAvailable(_DroidMediaBuffer *buffer)
{
    // Runs on the droidmedia output thread: read the buffer timestamp, pace
    // against the master (audio) clock, post the position, then hand the gralloc
    // buffer to the zero-copy sink.
    DroidMediaBufferInfo info;
    std::memset(&info, 0, sizeof(info));
    droid_media_buffer_get_info(buffer, &info);

    // Buffer-queue timestamps follow the Android graphics convention: nanoseconds.
    // (Verified by the per-frame delta in the log; ~33e6 ⇒ ns @ 30fps.) Audio pts
    // and this share one timeline: video us == ts/1000 == absolute file time.
    const qint64 ts = info.timestamp;
    const qint64 vptsUs = ts / 1000;

    if (m_hasAudio && masterClockUs() >= 0) {
        // A/V sync: audio is the master clock — hold the frame until audio
        // playback reaches its timestamp (present immediately if already late).
        // masterClockUs() interpolates between audio anchors so this is smooth.
        while (!m_stop) {
            const qint64 ahead = vptsUs - masterClockUs();
            if (ahead <= 2000) break; // within 2ms or late
            QThread::msleep(static_cast<unsigned long>(qMin<qint64>(ahead / 1000, 500)));
        }
    } else {
        // No audio stream (or audio not started yet): pace to wall clock anchored
        // at the first frame, as in stage 1.
        if (m_firstPtsUs < 0) { m_firstPtsUs = ts; m_clock.restart(); }
        const qint64 targetMs = (ts - m_firstPtsUs) / 1000000;
        const qint64 elapsed = m_clock.elapsed();
        if (targetMs > elapsed + 2 && !m_stop)
            QThread::msleep(static_cast<unsigned long>(qMin<qint64>(targetMs - elapsed, 1000)));
    }

    if (!m_stop) {
        // Pacing uses the absolute (offset) ts to match the audio clock, but the
        // UI shows the within-loop position (offset is 0 when not looping).
        const qint64 posUs = vptsUs - m_loopOffsetUs.load();
        emit postPosition((posUs > 0 ? posUs : 0) / 1000);
    }

    // Hand the gralloc buffer to the zero-copy sink (it owns the release once it
    // has wrapped/displayed it). With no sink, recycle it straight away.
    if (m_sink && !m_stop)
        m_sink->presentBuffer(buffer);
    else
        droid_media_buffer_release(buffer, nullptr, nullptr);
}

// ── GUI-thread state updates ─────────────────────────────────────────────────

void DroidCodecBackend::onPostState(int s)
{
    if (m_state == s)
        return;
    m_state = static_cast<State>(s);
    emit stateChanged();
}

void DroidCodecBackend::onPostPosition(qlonglong ms)
{
    // Buffers arrive in display order, so position is naturally monotonic during
    // play; we must NOT clamp it (that would block a backward seek's new position).
    m_positionMs = ms;
    emit positionChanged();
}

void DroidCodecBackend::onPostDuration(qlonglong ms)
{
    m_durationMs = ms;
    emit durationChanged();
    if (!m_seekable) {
        m_seekable = true;
        emit seekableChanged();
    }
}

void DroidCodecBackend::teardown()
{
    if (m_codec) {
        droid_media_codec_stop(m_codec);
        droid_media_codec_destroy(m_codec);
        m_codec = nullptr;
        m_queue = nullptr; // owned by the codec; just drop our reference
    }
    if (m_bsf) { av_bsf_free(&m_bsf); m_bsf = nullptr; }

    // Audio teardown (the audio thread is already joined by stop()).
    if (m_pa) { pa_simple_free(m_pa); m_pa = nullptr; }
    if (m_swr) { swr_free(&m_swr); m_swr = nullptr; }
    if (m_audioCtx) { avcodec_free_context(&m_audioCtx); m_audioCtx = nullptr; }
    {
        std::lock_guard<std::mutex> lk(m_aqMutex);
        for (AVPacket *p : m_aq) if (p) av_packet_free(&p);
        m_aq.clear();
    }
    m_audioStream = -1;
    m_hasAudio = false;
    { std::lock_guard<std::mutex> lk(m_clockMutex); m_clockValid = false; }

    if (m_fmt) { avformat_close_input(&m_fmt); m_fmt = nullptr; }
    m_videoStream = -1;
    m_positionMs = 0;
}
