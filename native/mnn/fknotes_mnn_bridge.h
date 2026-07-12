#ifndef FKNOTES_MNN_BRIDGE_H
#define FKNOTES_MNN_BRIDGE_H

#include <stdint.h>

#if defined(_WIN32)
#define FKNOTES_MNN_EXPORT __declspec(dllexport)
#else
#define FKNOTES_MNN_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*FkMnnEventCallback)(
    int64_t request_id,
    int32_t event_type,
    const uint8_t* data,
    int32_t data_size);

enum FkMnnEventType {
    FK_MNN_EVENT_LOADED = 0,
    FK_MNN_EVENT_TEXT_DELTA = 1,
    FK_MNN_EVENT_COMPLETED = 2,
    FK_MNN_EVENT_CANCELED = 3,
    FK_MNN_EVENT_UNLOADED = 4,
    FK_MNN_EVENT_ERROR = 5,
};

FKNOTES_MNN_EXPORT int32_t fk_mnn_is_available(void);
FKNOTES_MNN_EXPORT const char* fk_mnn_runtime_version(void);
FKNOTES_MNN_EXPORT int32_t fk_mnn_load_async(
    int64_t request_id,
    const char* config_path,
    const char* cache_path,
    const char* backend,
    int32_t threads,
    int32_t context_tokens,
    int32_t enable_thinking,
    int32_t enable_prompt_cache,
    FkMnnEventCallback callback);
FKNOTES_MNN_EXPORT int32_t fk_mnn_generate_async(
    int64_t request_id,
    const char* const* roles,
    const char* const* contents,
    int32_t message_count,
    const char* const* attachment_paths,
    const char* const* attachment_mime_types,
    const int32_t* attachment_message_indexes,
    int32_t attachment_count,
    int32_t max_new_tokens,
    double temperature,
    double top_p,
    int32_t top_k,
    int64_t timeout_milliseconds,
    FkMnnEventCallback callback);
FKNOTES_MNN_EXPORT int32_t fk_mnn_cancel(int64_t request_id);
FKNOTES_MNN_EXPORT int32_t fk_mnn_unload_async(
    int64_t request_id,
    FkMnnEventCallback callback);
FKNOTES_MNN_EXPORT void fk_mnn_free(void* data);

#ifdef __cplusplus
}
#endif

#endif
