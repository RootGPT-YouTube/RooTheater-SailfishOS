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
    Q_PROPERTY(bool playing READ playing NOTIFY stateChanged)
    Q_PROPERTY(qlonglong position READ position NOTIFY positionChanged)
    Q_PROPERTY(qlonglong duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(bool seekable READ seekable NOTIFY seekableChanged)
    Q_PROPERTY(bool loop READ loop WRITE setLoop NOTIFY loopChanged)

public:
    enum State { Stopped, Opening, Playing, Paused, Ended, Error };
    Q_ENUM(State)

    explicit DroidCodecBackend(QObject *parent = nullptr);
    ~DroidCodecBackend() override;

    VideoSurface *videoOutput() const { return m_output; }
    void setVideoOutput(VideoSurface *output);

    DroidVideoSink *videoSink() const { return m_sink; }
    void setVideoSink(DroidVideoSink *sink);

    State state() const { return m_state; }
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
    // internal: marshal state/position/duration updates from worker → GUI thread
    void postState(int s);
    void postPosition(qlonglong ms);
    void postDuration(qlonglong ms);

private slots:
    void onPostState(int s);
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
    void audioLoop();                 // runs on m_audioThread
    bool openInput(const QString &url);
    bool openAudio();                 // best-effort; video plays even if this fails
    void teardown();

    VideoSurface *m_output = nullptr;
    DroidVideoSink *m_sink = nullptr;
    State m_state = Stopped;
    qlonglong m_positionMs = 0;
    qlonglong m_durationMs = 0;
    bool m_seekable = false;

    // ffmpeg demux
    AVFormatContext *m_fmt = nullptr;
    AVBSFContext *m_bsf = nullptr;
    int m_videoStream = -1;

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
    qint64 m_clockBaseUs = 0;         // audible audio pts at the anchor
    qint64 m_clockBaseAtUs = 0;       // steady-clock time (us) of the anchor
    void setAudioAnchor(qint64 audibleUs);
    qint64 masterClockUs();           // interpolated audio clock, or -1 if invalid

    // worker + pacing
    std::thread m_demuxThread;
    std::atomic<bool> m_stop{false};
    std::atomic<bool> m_paused{false};
    QElapsedTimer m_clock;            // wall clock since first frame (no-audio fallback)
    qint64 m_firstPtsUs = -1;         // pts of first presented frame
    QString m_url;
    qint64 m_startMs = 0;             // seek target applied by openInput on restart
    // Loop: when the demux hits EOF it seeks back to 0 and keeps feeding the SAME
    // decoder (no teardown), adding a growing offset to every fed timestamp so the
    // A/V clock stays monotonic across loops. Position display subtracts it.
    std::atomic<bool> m_loop{false};
    std::atomic<qint64> m_loopOffsetUs{0};
};

#endif // DROIDCODECBACKEND_H
