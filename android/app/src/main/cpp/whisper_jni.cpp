#include <jni.h>
#include <whisper.h>
#include <string>
#include <vector>
#include <atomic>
#include <mutex>
#include <thread>
#include <cstring>
// The abort flag is reset from Kotlin (reset()) before the cancellation watcher starts, never on native entry.
static std::atomic<bool> cancelled{false};
// One cached model context. Kotlin serializes transcribe/release with a Mutex; g_lock makes the native side safe regardless.
static std::mutex g_lock;
static whisper_context *g_ctx = nullptr;
static std::string g_path;
extern "C" JNIEXPORT void JNICALL Java_dev_unpaged_android_ai_WhisperNative_cancel(JNIEnv *, jobject) { cancelled = true; }
extern "C" JNIEXPORT void JNICALL Java_dev_unpaged_android_ai_WhisperNative_reset(JNIEnv *, jobject) { cancelled = false; }
extern "C" JNIEXPORT void JNICALL Java_dev_unpaged_android_ai_WhisperNative_release(JNIEnv *, jobject) {
    std::lock_guard<std::mutex> guard(g_lock);
    if (g_ctx) { whisper_free(g_ctx); g_ctx = nullptr; g_path.clear(); }
}
extern "C" JNIEXPORT jstring JNICALL Java_dev_unpaged_android_ai_WhisperNative_transcribe(JNIEnv *env, jobject, jstring model, jfloatArray audio, jstring language) {
    std::lock_guard<std::mutex> guard(g_lock);
    const char *path = env->GetStringUTFChars(model, nullptr);
    std::string modelPath(path);
    env->ReleaseStringUTFChars(model, path);
    if (g_ctx && g_path != modelPath) { whisper_free(g_ctx); g_ctx = nullptr; g_path.clear(); }
    if (!g_ctx) {
        auto cp = whisper_context_default_params(); cp.use_gpu = false;
        g_ctx = whisper_init_from_file_with_params(modelPath.c_str(), cp);
        if (!g_ctx) { env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), "Could not load speech model."); return nullptr; }
        g_path = modelPath;
    }
    auto *ctx = g_ctx;
    std::vector<float> pcm(env->GetArrayLength(audio));
    env->GetFloatArrayRegion(audio, 0, pcm.size(), pcm.data());
    const char *langChars = env->GetStringUTFChars(language, nullptr);
    std::string lang(langChars);
    env->ReleaseStringUTFChars(language, langChars);
    auto params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.n_threads = std::min(4u, std::max(1u, std::thread::hardware_concurrency()));
    // Callers pass "auto" so the book's own language is detected rather than the phone's.
    const bool autoLanguage = lang == "auto" || whisper_lang_id(lang.c_str()) < 0;
    params.language = autoLanguage ? "auto" : lang.c_str();
    params.detect_language = false;
    params.translate = false; params.no_timestamps = true;
    params.no_speech_thold = 0.6f; params.suppress_blank = true; params.suppress_nst = true;
    params.print_realtime = false; params.print_progress = false; params.print_timestamps = false;
    params.abort_callback = [](void *) { return cancelled.load(); };
    int result = whisper_full(ctx, params, pcm.data(), pcm.size());
    // An explicit language that produced nothing: retry once with automatic detection.
    if (result == 0 && !autoLanguage && whisper_full_n_segments(ctx) == 0 && !cancelled) {
        params.language = "auto"; result = whisper_full(ctx, params, pcm.data(), pcm.size());
    }
    std::string text;
    if (result == 0 && !cancelled) for (int i = 0; i < whisper_full_n_segments(ctx); ++i) text += whisper_full_get_segment_text(ctx, i);
    if (result != 0 && !cancelled) { env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), "Could not transcribe audio."); return nullptr; }
    // JNI NewStringUTF expects modified UTF-8; use Java's standard UTF-8 decoder for multilingual text.
    jbyteArray bytes = env->NewByteArray(text.size());
    env->SetByteArrayRegion(bytes, 0, text.size(), reinterpret_cast<const jbyte *>(text.data()));
    auto cls = env->FindClass("java/lang/String");
    return static_cast<jstring>(env->NewObject(cls, env->GetMethodID(cls, "<init>", "([BLjava/lang/String;)V"), bytes, env->NewStringUTF("UTF-8")));
}
