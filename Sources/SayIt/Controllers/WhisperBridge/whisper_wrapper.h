#pragma once
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 不透明上下文句柄
typedef struct WhisperContext WhisperContext;

/// 加载模型，返回 NULL 表示失败
WhisperContext * whisper_wrapper_init(const char * model_path);

/// 释放上下文
void whisper_wrapper_free(WhisperContext * ctx);

/// 转写 PCM float32 数据（16 kHz 单声道），结果写入 out_text（调用方负责 free）
/// initial_prompt 可为 NULL，表示使用默认提示
/// 返回 true 成功，false 失败
bool whisper_wrapper_transcribe(
    WhisperContext * ctx,
    const float * pcm,
    int   n_samples,
    const char * language,       // "zh" / "en" / "auto"
    const char * initial_prompt, // 可为 NULL
    char ** out_text              // 调用方用 free() 释放
);

#ifdef __cplusplus
}
#endif
