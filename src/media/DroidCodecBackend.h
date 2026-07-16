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

#ifndef DROIDCODECBACKEND_H
#define DROIDCODECBACKEND_H

#include <QObject>
#include <QString>
#include <QByteArray>
#include <QImage>
#include <QElapsedTimer>
#include <atomic>
#include <thread>
#include <deque>
#include <mutex>
#include <condition_variable>

#include "VideoSurface.h"

class DroidVideoSink;
struct AVFormatContext;
struct AVBSFContext;
struct AVCodecParameters;
struct AVCodecContext;
struct AVPacket;
struct SwrContext;
struct pa_simple;
struct _DroidMediaCodec;
struct _DroidMediaBuffer;
struct _DroidMediaBufferQueue;

// DroidCodecBackend is the Layer 1 direct-HW player (v0.3). It owns the whole
// pipeline droidmedia can't: ffmpeg demuxes the container and a bitstream filter
// turns the elementary stream into Annex-B, which is fed to a droidmedia OMX
// hardware decoder; decoded frames come back as gralloc buffers via the codec's
// DroidMediaBufferQueue and are drawn zero-copy by DroidVideoSink (each
// DroidMediaBuffer wrapped in an EGLImage on a GL_TEXTURE_EXTERNAL_OES node — no
// CPU touch of pixels). Audio is decoded with ffmpeg + libswresample and played
// via PulseAudio on a dedicated thread that is the A/V master clock; video paces
// against it. Seek restarts the pipeline at the target (flushing the live OMX
// decoder deadlocks against the buffers the sink still holds).
class DroidCodecBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(VideoSurface *videoOutput READ videoOutput WRITE setVideoOutput NOTIFY videoOutputChanged)
    Q_PROPERTY(DroidVideoSink *videoSink READ videoSink WRITE setVideoSink NOTIFY videoSinkChanged)
    Q_PROPERTY(State state READ state NOTIFY stateChanged)
    Q_PROPERTY(ErrorKind errorKind READ errorKind NOTIFY stateChanged)
    Q_PROPERTY(bool playing READ playing NOTIFY stateChanged)
    Q_PROPERTY(qlonglong position READ position NOTIFY positionChanged)
    Q_PROPERTY(qlonglong duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(bool seekable READ seekable NOTIFY seekableChanged)
    Q_PROPERTY(bool loop READ loop WRITE setLoop NOTIFY loopChanged)

public:
    enum State { Stopped, Opening, Playing, Paused, Ended, Error };
    Q_ENUM(State)

    // Why the backend went to Error — so the UI can say "network" vs "demux" vs
    // "decode" instead of a single misleading "hardware decode error", and so the
    // auto HW→SW fallback only kicks in for faults libVLC could actually recover
    // (decode/unsupported), not for a dead network or unreadable container.
    enum ErrorKind { ErrNone, ErrNetwork, ErrDemux, ErrUnsupported, ErrDecode };
    Q_ENUM(ErrorKind)

    explicit DroidCodecBackend(QObject *parent = nullptr);
    ~DroidCodecBackend() override;

    VideoSurface *videoOutput() const { return m_output; }
    void setVideoOutput(VideoSurface *output);

    DroidVideoSink *videoSink() const { return m_sink; }
    void setVideoSink(DroidVideoSink *sink);

    State state() const { return m_state; }
    ErrorKind errorKind() const { return m_errorKind; }
    bool playing() const { return m_state == Playing; }
    qlonglong position() const { return m_positionMs; }
    qlonglong duration() const { return m_durationMs; }
    bool seekable() const { return m_seekable; }
    bool loop() const { return m_loop.load(); }
    void setLoop(bool on);

    Q_INVOKABLE void play(const QString &url);
    Q_INVOKABLE void pause();
    Q_INVOKABLE void togglePause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void seek(qlonglong ms);

    // Called from the droidmedia buffer-queue frame_available thunk (decode
    // thread): a decoded gralloc DroidMediaBuffer ready on the codec's output
    // queue. Public so the C callback can reach it; not meant for QML.
    void onFrameAvailable(_DroidMediaBuffer *buffer);

signals:
    void videoOutputChanged();
    void videoSinkChanged();
    void stateChanged();
    void positionChanged();
    void durationChanged();
    void seekableChanged();
    void loopChanged();
    void frameReady(const QImage &frame);
    // internal: marshal state/position/duration updates from worker → GUI thread.
    // postState carries the generation of the pipeline that emitted it (see m_gen).
    void postState(int s, int gen);
    void postPosition(qlonglong ms);
    void postDuration(qlonglong ms);

private slots:
    void onPostState(int s, int gen);
    void onPostPosition(qlonglong ms);
    void onPostDuration(qlonglong ms);

private:
    // droidmedia codec callbacks (decode thread). The buffer-queue thunks are
    // file-statics in the .cpp (their arg types can't be forward-declared) and
    // call onFrameAvailable().
    static void eosCb(void *data);
    static void errorCb(void *data, int err);
    static int sizeChangedCb(void *data, int32_t width, int32_t height);

    void demuxLoop();                 // runs on m_demuxThread
    void videoFeedLoop();             // runs on m_videoFeedThread
    void audioLoop();                 // runs on m_audioThread
    void presentLoop();               // runs on m_presentThread
    // Pace one decoded frame against the master clock, then hand it to the sink.
    void paceAndPresent(_DroidMediaBuffer *buffer, qint64 vptsUs);
    bool openInput(const QString &url);
    bool openAudio();                 // best-effort; video plays even if this fails
    void teardown();
    void emitState(int s);            // postState stamped with the current generation

    VideoSurface *m_output = nullptr;
    DroidVideoSink *m_sink = nullptr;
    State m_state = Stopped;
    ErrorKind m_errorKind = ErrNone;
    qlonglong m_positionMs = 0;
    qlonglong m_durationMs = 0;
    bool m_seekable = false;

    // ffmpeg demux
    AVFormatContext *m_fmt = nullptr;
    AVBSFContext *m_bsf = nullptr;
    int m_videoStream = -1;

    // MPEG-TS (and other elementary streams) carry no avcC/hvcC config box — the
    // H.264 SPS/PPS arrive in-band as Annex-B. droidmedia's create_decoder needs
    // that config up front, so for such streams openInput() pre-reads packets to
    // find the SPS/PPS, synthesizes the avcC into m_codecData, and keeps the
    // already-read packets in m_primePackets for the demux loop to replay first
    // (no frames lost — works for live streams that can't be rewound).
    QByteArray m_codecData;
    std::deque<AVPacket *> m_primePackets;

    // droidmedia decoder + its output gralloc buffer queue
    _DroidMediaCodec *m_codec = nullptr;
    _DroidMediaBufferQueue *m_queue = nullptr;

    // audio: ffmpeg avcodec decode → libswresample (S16) → PulseAudio (pa_simple).
    // The audio thread is the MASTER clock; video paces against masterClockUs().
    int m_audioStream = -1;
    AVCodecContext *m_audioCtx = nullptr;
    SwrContext *m_swr = nullptr;
    pa_simple *m_pa = nullptr;
    int m_outRate = 48000;
    int m_outChannels = 2;
    std::atomic<bool> m_hasAudio{false};
    std::thread m_audioThread;
    std::deque<AVPacket *> m_aq;       // demux → audio thread packet queue
    std::mutex m_aqMutex;
    std::condition_variable m_aqNotEmpty;
    std::condition_variable m_aqNotFull;
    // Master clock = the audio playhead, kept CONTINUOUS by interpolation: the
    // audio thread re-anchors (audio pts − PulseAudio latency, steady-clock now)
    // each frame, and masterClockUs() extrapolates with wall time between anchors
    // so video pacing is smooth instead of stepping at the audio-frame cadence.
    std::mutex m_clockMutex;
    bool m_clockValid = false;        // false ⇒ no audio yet → video uses wall clock
    bool m_clockFrozen = false;       // true while paused ⇒ clock stops extrapolating
    qint64 m_clockBaseUs = 0;         // audible audio pts at the anchor
    qint64 m_clockBaseAtUs = 0;       // steady-clock time (us) of the anchor
    void setAudioAnchor(qint64 audibleUs);
    qint64 masterClockUs();           // interpolated audio clock, or -1 if invalid
    void freezeClock(bool freeze);    // pause/resume: stop the clock running away

    // Decoupled present: onFrameAvailable() enqueues the decoded gralloc buffer and
    // returns at once, so a pacing wait never runs on the droidmedia output thread.
    // That thread serialises frame delivery — an in-callback sleep blocks the NEXT
    // frame and makes the HW decoder deliver in bursts (the startup stutter).
    // m_presentThread pops frames and paces them instead. The
    // bounded depth gives natural backpressure and caps gralloc buffers held out of
    // the decoder's pool (sink holds ≤2 more).
    struct PendingFrame { _DroidMediaBuffer *buf; qint64 vptsUs; };
    std::deque<PendingFrame> m_frameQ;
    std::mutex m_frameQMutex;
    std::condition_variable m_frameQNotEmpty;
    std::condition_variable m_frameQNotFull;
    std::thread m_presentThread;

    // Decoupled video feed: the demux thread must NOT call droid_media_codec_queue
    // directly — it blocks ~200-290 ms while the decoder re-primes at a loop seam,
    // and the same thread also feeds m_aq, so a video stall would starve audio and
    // underrun PulseAudio (the loop-restart crackle). The demux builds the input
    // copy + timestamp here and m_videoFeedThread does the (blocking) codec queue.
    // Deeper than m_aq so audio backpressure paces the pipeline and a re-prime stall
    // is absorbed without the demux ever blocking off the audio feed. data == null is
    // an EOF marker telling the feed thread to drain the decoder (end-of-stream).
    struct VideoPacket { void *data; int size; qint64 ts; bool sync; };
    std::deque<VideoPacket> m_vq;
    std::mutex m_vqMutex;
    std::condition_variable m_vqNotEmpty;
    std::condition_variable m_vqNotFull;
    std::thread m_videoFeedThread;

    // worker + pacing
    std::thread m_demuxThread;
    // Pipeline generation, bumped by every play() (a seek is a restart, so it bumps
    // too). State updates are queued to the GUI thread, so one emitted by the pipeline
    // being torn down can land AFTER its successor is already running — an Ended from
    // the codec's EOS callback during teardown() then looked like the file had really
    // finished and auto-advanced the queue to the next track. onPostState drops any
    // update whose generation is no longer current.
    std::atomic<int> m_gen{0};
    std::atomic<bool> m_stop{false};
    std::atomic<bool> m_paused{false};
    QElapsedTimer m_clock;            // wall clock since first frame (no-audio fallback)
    qint64 m_firstPtsUs = -1;         // pts of first presented frame
    qint64 m_lastPosEmitMs = -1;      // last UI position emit (throttle to ~5 Hz)
    QString m_url;
    qint64 m_startMs = 0;             // seek target applied by openInput on restart
    // Loop: when the demux hits EOF it seeks back to 0 and keeps feeding the SAME
    // decoder (no teardown), adding a growing offset to every fed timestamp so the
    // A/V clock stays monotonic across loops. Position display subtracts it.
    std::atomic<bool> m_loop{false};
    std::atomic<qint64> m_loopOffsetUs{0};
};

#endif // DROIDCODECBACKEND_H
