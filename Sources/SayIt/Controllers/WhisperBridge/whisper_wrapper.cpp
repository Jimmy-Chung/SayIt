#include "whisper_wrapper.h"
#include "whisper.h"
#include <cstring>
#include <cstdlib>
#include <string>

struct WhisperContext {
    whisper_context * ctx = nullptr;
};

WhisperContext * whisper_wrapper_init(const char * model_path) {
    whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = true;

    whisper_context * ctx = whisper_init_from_file_with_params(model_path, cparams);
    if (!ctx) return nullptr;

    auto * handle = new WhisperContext();
    handle->ctx = ctx;
    return handle;
}

void whisper_wrapper_free(WhisperContext * handle) {
    if (!handle) return;
    if (handle->ctx) whisper_free(handle->ctx);
    delete handle;
}

bool whisper_wrapper_transcribe(
    WhisperContext * handle,
    const float * pcm,
    int n_samples,
    const char * language,
    const char * initial_prompt,
    char ** out_text)
{
    if (!handle || !handle->ctx || !pcm || n_samples <= 0) return false;

    whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    wparams.print_progress   = false;
    wparams.print_special    = false;
    wparams.print_realtime   = false;
    wparams.print_timestamps = false;
    wparams.translate        = false;
    wparams.single_segment   = false;
    wparams.no_context       = false;
    wparams.language         = language && strlen(language) > 0 ? language : "auto";
    wparams.n_threads        = 4;

    // 构建 initial_prompt：默认中文提示 + 用户自定义词典词汇
    std::string prompt = "\xe4\xbb\xa5\xe4\xb8\x8b\xe6\x98\xaf\xe6\x99\xae\xe9\x80\x9a\xe8\xaf\x9d\xe7\x9a\x84\xe5\x8f\xa5\xe5\xad\x90\xef\xbc\x8c\xe4\xbd\xbf\xe7\x94\xa8\xe7\xae\x80\xe4\xbd\x93\xe4\xb8\xad\xe6\x96\x87\xe8\xbe\x93\xe5\x87\xba\xe3\x80\x82";
    // = "以下是普通话的句子，使用简体中文输出。"
    if (initial_prompt && strlen(initial_prompt) > 0) {
        prompt += " ";
        prompt += initial_prompt;
    }
    wparams.initial_prompt = prompt.c_str();

    if (whisper_full(handle->ctx, wparams, pcm, n_samples) != 0) {
        return false;
    }

    std::string result;
    const int n_segments = whisper_full_n_segments(handle->ctx);
    for (int i = 0; i < n_segments; ++i) {
        const char * text = whisper_full_get_segment_text(handle->ctx, i);
        if (text) result += text;
    }

    *out_text = (char *)malloc(result.size() + 1);
    if (!*out_text) return false;
    memcpy(*out_text, result.c_str(), result.size() + 1);
    return true;
}
