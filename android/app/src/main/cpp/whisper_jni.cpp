#include <jni.h>
#include <whisper.h>
#include <string>
#include <vector>
#include <atomic>
#include <thread>
static std::atomic<bool> cancelled{false};
extern "C" JNIEXPORT void JNICALL Java_dev_unpaged_android_ai_WhisperNative_cancel(JNIEnv *, jobject) { cancelled = true; }
extern "C" JNIEXPORT jstring JNICALL Java_dev_unpaged_android_ai_WhisperNative_transcribe(JNIEnv *env, jobject, jstring model, jfloatArray audio, jstring language) {
    cancelled = false;
    const char *path = env->GetStringUTFChars(model, nullptr);
    auto cp = whisper_context_default_params(); cp.use_gpu = false;
    auto *ctx = whisper_init_from_file_with_params(path, cp);
    env->ReleaseStringUTFChars(model, path);
    if (!ctx) { env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), "Could not load speech model."); return nullptr; }
    std::vector<float> pcm(env->GetArrayLength(audio));
    env->GetFloatArrayRegion(audio, 0, pcm.size(), pcm.data());
    const char *lang = env->GetStringUTFChars(language, nullptr);
    auto params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.n_threads = std::min(4u, std::max(1u, std::thread::hardware_concurrency()));
    params.language = whisper_lang_id(lang) < 0 ? "auto" : lang;
    params.translate = false; params.no_timestamps = true;
    params.print_realtime = false; params.print_progress = false; params.print_timestamps = false;
    params.abort_callback = [](void *) { return cancelled.load(); };
    int result = whisper_full(ctx, params, pcm.data(), pcm.size());
    // Unsupported language or empty transcription: retry using automatic detection.
    if (result == 0 && whisper_full_n_segments(ctx) == 0 && !cancelled) {
        params.language = "auto"; result = whisper_full(ctx, params, pcm.data(), pcm.size());
    }
    std::string text;
    if (result == 0 && !cancelled) for (int i = 0; i < whisper_full_n_segments(ctx); ++i) text += whisper_full_get_segment_text(ctx, i);
    whisper_free(ctx); env->ReleaseStringUTFChars(language, lang);
    if (result != 0 && !cancelled) { env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), "Could not transcribe audio."); return nullptr; }
    // JNI NewStringUTF expects modified UTF-8; use Java's standard UTF-8 decoder for multilingual text.
    jbyteArray bytes = env->NewByteArray(text.size());
    env->SetByteArrayRegion(bytes, 0, text.size(), reinterpret_cast<const jbyte *>(text.data()));
    auto cls = env->FindClass("java/lang/String");
    return static_cast<jstring>(env->NewObject(cls, env->GetMethodID(cls, "<init>", "([BLjava/lang/String;)V"), bytes, env->NewStringUTF("UTF-8")));
}
