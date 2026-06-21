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

#include "DroidVideoSink.h"

#include <QSGGeometryNode>
#include <QSGGeometry>
#include <QSGMaterial>
#include <QSGMaterialShader>
#include <QMutexLocker>
#include <QDebug>

#include <cstring>

// EGL/GLES BEFORE droidmedia.h: droidmedia re-typedefs EGLDisplay/EGLSyncKHR as
// void* (identical to the canonical EGL ones, so harmless once these are first).
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>

extern "C" {
#include <droidmedia.h>
}

namespace {

// EGLImage / external-texture extension entry points (resolved once, lazily, on
// the render thread where an EGL context is current).
PFNEGLCREATEIMAGEKHRPROC                 pEglCreateImageKHR = nullptr;
PFNEGLDESTROYIMAGEKHRPROC                pEglDestroyImageKHR = nullptr;
PFNGLEGLIMAGETARGETTEXTURE2DOESPROC      pGlEGLImageTargetTexture2DOES = nullptr;

bool resolveEglExt()
{
    if (!pEglCreateImageKHR) {
        pEglCreateImageKHR = (PFNEGLCREATEIMAGEKHRPROC)eglGetProcAddress("eglCreateImageKHR");
        pEglDestroyImageKHR = (PFNEGLDESTROYIMAGEKHRPROC)eglGetProcAddress("eglDestroyImageKHR");
        pGlEGLImageTargetTexture2DOES =
            (PFNGLEGLIMAGETARGETTEXTURE2DOESPROC)eglGetProcAddress("glEGLImageTargetTexture2DOES");
    }
    return pEglCreateImageKHR && pEglDestroyImageKHR && pGlEGLImageTargetTexture2DOES;
}

// ── External-OES material: samples a GL_TEXTURE_EXTERNAL_OES (the YUV→RGB and
//    tiled/UBWC layout are handled by the driver's external sampler). ──────────
class ExternalOESMaterial : public QSGMaterial
{
public:
    ExternalOESMaterial() { setFlag(Blending, false); }
    QSGMaterialType *type() const override { static QSGMaterialType t; return &t; }
    QSGMaterialShader *createShader() const override;
    GLuint textureId = 0;
};

class ExternalOESShader : public QSGMaterialShader
{
public:
    const char *vertexShader() const override
    {
        return
            "attribute highp vec4 aVertex;\n"
            "attribute highp vec2 aTexCoord;\n"
            "uniform highp mat4 qt_Matrix;\n"
            "varying highp vec2 vTexCoord;\n"
            "void main() {\n"
            "    gl_Position = qt_Matrix * aVertex;\n"
            "    vTexCoord = aTexCoord;\n"
            "}\n";
    }
    const char *fragmentShader() const override
    {
        return
            "#extension GL_OES_EGL_image_external : require\n"
            "uniform samplerExternalOES uTex;\n"
            "uniform lowp float qt_Opacity;\n"
            "varying highp vec2 vTexCoord;\n"
            "void main() {\n"
            "    gl_FragColor = texture2D(uTex, vTexCoord) * qt_Opacity;\n"
            "}\n";
    }
    char const *const *attributeNames() const override
    {
        static char const *const names[] = { "aVertex", "aTexCoord", nullptr };
        return names;
    }
    void initialize() override
    {
        QSGMaterialShader::initialize();
        m_idMatrix = program()->uniformLocation("qt_Matrix");
        m_idOpacity = program()->uniformLocation("qt_Opacity");
        program()->setUniformValue("uTex", 0); // sampler on texture unit 0
    }
    void updateState(const RenderState &state, QSGMaterial *newMat, QSGMaterial *) override
    {
        if (state.isMatrixDirty())
            program()->setUniformValue(m_idMatrix, state.combinedMatrix());
        if (state.isOpacityDirty())
            program()->setUniformValue(m_idOpacity, state.opacity());
        GLuint tex = static_cast<ExternalOESMaterial *>(newMat)->textureId;
        if (tex) {
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_EXTERNAL_OES, tex);
        }
    }
private:
    int m_idMatrix = -1;
    int m_idOpacity = -1;
};

QSGMaterialShader *ExternalOESMaterial::createShader() const { return new ExternalOESShader; }

} // namespace

// ─────────────────────────────────────────────────────────────────────────────

DroidVideoSink::DroidVideoSink(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
}

DroidVideoSink::~DroidVideoSink()
{
    // GL resources are torn down on the render thread (releaseResources); here we
    // just make sure no droidmedia buffers are still pinned.
    reset();
}

void DroidVideoSink::releaseBuffer(_DroidMediaBuffer *buffer)
{
    if (buffer)
        droid_media_buffer_release(buffer, eglGetCurrentDisplay(), nullptr);
}

void DroidVideoSink::presentBuffer(_DroidMediaBuffer *buffer)
{
    // droidmedia output thread: stash the newest buffer; if a previous pending
    // one was never picked up by the render thread, hand it straight back so the
    // pool never starves. Then poke the render thread.
    _DroidMediaBuffer *drop = nullptr;
    {
        QMutexLocker lock(&m_mutex);
        drop = m_pending;
        m_pending = buffer;
    }
    if (drop)
        droid_media_buffer_release(drop, nullptr, nullptr); // never rendered → no GL fence
    QMetaObject::invokeMethod(this, "requestUpdate", Qt::QueuedConnection);
}

void DroidVideoSink::reset()
{
    // Drop references and return the buffers to the pool. Called before the codec
    // is destroyed (backend stop/seek) so the queue is still alive. The live
    // EGLImage can't be destroyed here (eglDestroyImageKHR needs the render
    // thread's context), so queue it for the render thread and poke a frame.
    _DroidMediaBuffer *p, *c;
    {
        QMutexLocker lock(&m_mutex);
        p = m_pending;     m_pending = nullptr;
        c = m_current;     m_current = nullptr;
        if (m_currentImage) { m_deadImages.append(m_currentImage); m_currentImage = nullptr; }
    }
    if (p) droid_media_buffer_release(p, nullptr, nullptr);
    if (c) droid_media_buffer_release(c, nullptr, nullptr);
    QMetaObject::invokeMethod(this, "requestUpdate", Qt::QueuedConnection);
}

QSGNode *DroidVideoSink::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    // Pick up the newest decoded buffer (if any) + any EGLImages abandoned by
    // reset() (stop/seek), which only this thread can destroy.
    _DroidMediaBuffer *newBuf = nullptr;
    QVector<void *> dead;
    {
        QMutexLocker lock(&m_mutex);
        newBuf = m_pending;
        m_pending = nullptr;
        dead.swap(m_deadImages);
    }
    if (pEglDestroyImageKHR)
        for (void *img : dead)
            pEglDestroyImageKHR(eglGetCurrentDisplay(), img);

    QSGGeometryNode *node = static_cast<QSGGeometryNode *>(oldNode);
    if (!node) {
        if (!newBuf)
            return nullptr; // nothing decoded yet → draw nothing
        if (!resolveEglExt()) {
            qWarning("[RT] DroidVideoSink: EGLImage/external-OES extensions unavailable");
            releaseBuffer(newBuf);
            return nullptr;
        }
        node = new QSGGeometryNode;
        QSGGeometry *geo = new QSGGeometry(QSGGeometry::defaultAttributes_TexturedPoint2D(), 4);
        geo->setDrawingMode(GL_TRIANGLE_STRIP);
        node->setGeometry(geo);
        node->setFlag(QSGNode::OwnsGeometry);
        ExternalOESMaterial *mat = new ExternalOESMaterial;
        glGenTextures(1, &m_texture);
        glBindTexture(GL_TEXTURE_EXTERNAL_OES, m_texture);
        glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        mat->textureId = m_texture;
        node->setMaterial(mat);
        node->setFlag(QSGNode::OwnsMaterial);
    }

    if (newBuf) {
        DroidMediaBufferInfo info;
        std::memset(&info, 0, sizeof(info));
        droid_media_buffer_get_info(newBuf, &info);
        m_srcW = info.width > 0 ? info.width : m_srcW;
        m_srcH = info.height > 0 ? info.height : m_srcH;
        if (info.width > 0 && info.height > 0) {
            m_cropL = float(info.crop_rect.left)   / info.width;
            m_cropR = float(info.crop_rect.right)  / info.width;
            m_cropT = float(info.crop_rect.top)    / info.height;
            m_cropB = float(info.crop_rect.bottom) / info.height;
        }

        EGLDisplay dpy = eglGetCurrentDisplay();
        EGLint attrs[] = { EGL_IMAGE_PRESERVED_KHR, EGL_TRUE, EGL_NONE };
        EGLImageKHR img = pEglCreateImageKHR(dpy, EGL_NO_CONTEXT, EGL_NATIVE_BUFFER_ANDROID,
                                             (EGLClientBuffer)newBuf, attrs);
        if (img == EGL_NO_IMAGE_KHR) {
            qWarning("[RT] DroidVideoSink: eglCreateImageKHR failed (egl err 0x%x)", eglGetError());
            releaseBuffer(newBuf);
        } else {
            glBindTexture(GL_TEXTURE_EXTERNAL_OES, m_texture);
            pGlEGLImageTargetTexture2DOES(GL_TEXTURE_EXTERNAL_OES, (GLeglImageOES)img);
            // Swap in the new frame under the lock (reset() may run concurrently
            // on the GUI thread), then free the previous frame's image + buffer.
            void *oldImg; _DroidMediaBuffer *oldBuf;
            {
                QMutexLocker lock(&m_mutex);
                oldImg = m_currentImage; oldBuf = m_current;
                m_currentImage = img;    m_current = newBuf;
            }
            if (oldImg) pEglDestroyImageKHR(dpy, oldImg);
            if (oldBuf) releaseBuffer(oldBuf);
        }
    }

    // Letterbox the visible (cropped) picture inside the item, preserving aspect.
    const float W = float(width());
    const float H = float(height());
    const float cropPixW = (m_cropR - m_cropL) * m_srcW;
    const float cropPixH = (m_cropB - m_cropT) * m_srcH;
    if (W <= 0 || H <= 0 || cropPixW <= 0 || cropPixH <= 0)
        return node;
    const float aspect = cropPixW / cropPixH;
    float tw = W, th = W / aspect;
    if (th > H) { th = H; tw = H * aspect; }
    const float x0 = (W - tw) * 0.5f, y0 = (H - th) * 0.5f;
    const float x1 = x0 + tw,         y1 = y0 + th;

    // Triangle strip: TL, BL, TR, BR. Texture origin is top-left (Android buffer),
    // so V increases downward → top vertices map to cropT, bottom to cropB.
    QSGGeometry::TexturedPoint2D *v = node->geometry()->vertexDataAsTexturedPoint2D();
    v[0].set(x0, y0, m_cropL, m_cropT);
    v[1].set(x0, y1, m_cropL, m_cropB);
    v[2].set(x1, y0, m_cropR, m_cropT);
    v[3].set(x1, y1, m_cropR, m_cropB);

    node->markDirty(QSGNode::DirtyGeometry | QSGNode::DirtyMaterial);
    return node;
}

void DroidVideoSink::releaseResources()
{
    // Render thread, EGL context current: free the GL texture + live/queued images.
    EGLDisplay dpy = eglGetCurrentDisplay();
    QVector<void *> dead;
    {
        QMutexLocker lock(&m_mutex);
        dead.swap(m_deadImages);
        if (m_currentImage) { dead.append(m_currentImage); m_currentImage = nullptr; }
    }
    if (pEglDestroyImageKHR)
        for (void *img : dead)
            pEglDestroyImageKHR(dpy, img);
    if (m_texture) {
        glDeleteTextures(1, &m_texture);
        m_texture = 0;
    }
}
