#include "fknotes_mnn_bridge.h"

#include <atomic>
#include <algorithm>
#include <chrono>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#if defined(FKNOTES_MNN_RUNTIME)
#include <MNN/llm/llm.hpp>
#endif

namespace {

constexpr const char* kRuntimeVersion = "3.6.0";

void emit_event(
    FkMnnEventCallback callback,
    int64_t request_id,
    int32_t event_type,
    const std::string& data = {}) {
    if (callback == nullptr) {
        return;
    }
    uint8_t* copy = nullptr;
    if (!data.empty()) {
        copy = static_cast<uint8_t*>(std::malloc(data.size()));
        if (copy == nullptr) {
            return;
        }
        std::memcpy(copy, data.data(), data.size());
    }
    callback(request_id, event_type, copy, static_cast<int32_t>(data.size()));
}

std::string json_escape(const std::string& value) {
    std::ostringstream output;
    for (const unsigned char character : value) {
        switch (character) {
            case '\\': output << "\\\\"; break;
            case '"': output << "\\\""; break;
            case '\b': output << "\\b"; break;
            case '\f': output << "\\f"; break;
            case '\n': output << "\\n"; break;
            case '\r': output << "\\r"; break;
            case '\t': output << "\\t"; break;
            default:
                if (character < 0x20) {
                    const char* digits = "0123456789abcdef";
                    output << "\\u00" << digits[character >> 4] << digits[character & 0x0f];
                } else {
                    output << character;
                }
        }
    }
    return output.str();
}

// MNN's generated string is cumulative UTF-8, but an individual token may
// contribute only part of a multi-byte character. Never publish the incomplete
// suffix to Dart: decoding each byte fragment independently would turn one
// Chinese character into multiple U+FFFD replacement characters.
std::size_t complete_utf8_prefix_size(const std::string& value) {
    if (value.empty()) {
        return 0;
    }
    const std::size_t end = value.size();
    std::size_t start = end - 1;
    while (start > 0 &&
           (static_cast<unsigned char>(value[start]) & 0xC0) == 0x80) {
        --start;
    }
    const unsigned char lead = static_cast<unsigned char>(value[start]);
    std::size_t expected = 1;
    if ((lead & 0xE0) == 0xC0) {
        expected = 2;
    } else if ((lead & 0xF0) == 0xE0) {
        expected = 3;
    } else if ((lead & 0xF8) == 0xF0) {
        expected = 4;
    }
    return end - start < expected ? start : end;
}

#if defined(FKNOTES_MNN_RUNTIME)

using MNN::Transformer::ChatMessage;
using MNN::Transformer::ChatMessages;
using MNN::Transformer::Llm;
using MNN::Transformer::LlmContext;
using MNN::Transformer::LlmStatus;
using MNN::Transformer::MultimodalPrompt;

struct MultimodalAttachment {
    int32_t message_index;
    std::string path;
    std::string mime_type;
};

void replace_all(std::string& value, const std::string& from, const std::string& to) {
    std::size_t position = 0;
    while ((position = value.find(from, position)) != std::string::npos) {
        value.replace(position, from.size(), to);
        position += to.size();
    }
}

void escape_multimodal_tags(std::string& value) {
    replace_all(value, "<img>", "&lt;img&gt;");
    replace_all(value, "</img>", "&lt;/img&gt;");
    replace_all(value, "<audio>", "&lt;audio&gt;");
    replace_all(value, "</audio>", "&lt;/audio&gt;");
}

bool is_image_mime(const std::string& mime_type) {
    return mime_type == "image/jpeg" || mime_type == "image/png" ||
           mime_type == "image/webp" || mime_type == "image/bmp";
}

bool is_audio_mime(const std::string& mime_type) {
    return mime_type == "audio/wav" || mime_type == "audio/x-wav";
}

bool prepare_multimodal_messages(
    ChatMessages& messages,
    const std::vector<MultimodalAttachment>& attachments,
    std::string& error) {
    if (attachments.empty()) {
        return true;
    }
    for (auto& message : messages) {
        escape_multimodal_tags(message.second);
    }
    std::vector<std::string> prefixes(messages.size());
    for (const auto& attachment : attachments) {
        if (attachment.message_index < 0 ||
            static_cast<std::size_t>(attachment.message_index) >= messages.size()) {
            error = "多模态附件关联的消息无效";
            return false;
        }
        auto& message = messages[static_cast<std::size_t>(attachment.message_index)];
        if (message.first != "user") {
            error = "多模态附件只能附加在用户消息中";
            return false;
        }
        if (attachment.path.empty() || attachment.path.find('<') != std::string::npos ||
            attachment.path.find('>') != std::string::npos) {
            error = "多模态附件路径无效";
            return false;
        }
        std::ifstream input(attachment.path, std::ios::binary);
        if (!input.good()) {
            error = "无法读取多模态附件";
            return false;
        }
        auto& prefix = prefixes[static_cast<std::size_t>(attachment.message_index)];
        if (is_image_mime(attachment.mime_type)) {
            prefix += "<img>" + attachment.path + "</img>\n";
        } else if (is_audio_mime(attachment.mime_type)) {
            prefix += "<audio>" + attachment.path + "</audio>\n";
        } else {
            error = "MNN 原生层不支持这种多模态附件格式";
            return false;
        }
    }
    for (std::size_t index = 0; index < messages.size(); ++index) {
        if (!prefixes[index].empty()) {
            messages[index].second = prefixes[index] + messages[index].second;
        }
    }
    return true;
}

class Runtime {
public:
    bool load_async(
        int64_t request_id,
        std::string config_path,
        std::string cache_path,
        std::string backend,
        int threads,
        int context_tokens,
        bool enable_thinking,
        bool enable_prompt_cache,
        FkMnnEventCallback callback) {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (busy_) {
                return false;
            }
            busy_ = true;
        }
        std::thread([
            this,
            request_id,
            config_path = std::move(config_path),
            cache_path = std::move(cache_path),
            backend = std::move(backend),
            threads,
            context_tokens,
            enable_thinking,
            enable_prompt_cache,
            callback]() {
            auto started = std::chrono::steady_clock::now();
            std::unique_ptr<Llm> candidate(Llm::createLLM(config_path));
            if (!candidate) {
                finish_with_error(callback, request_id, "无法创建 MNN LLM，请检查 config.json");
                return;
            }
            std::ostringstream options;
            options << "{\"backend_type\":\"" << json_escape(backend)
                    << "\",\"thread_num\":" << threads
                    << ",\"max_all_tokens\":" << context_tokens
                    << ",\"use_mmap\":true"
                    << ",\"sampler_type\":\"mixed\""
                    << ",\"temperature\":0.7,\"topP\":0.95,\"topK\":40"
                    << ",\"prompt_cache\":" << (enable_prompt_cache ? "true" : "false")
                    << ",\"jinja\":{\"context\":{\"enable_thinking\":"
                    << (enable_thinking ? "true" : "false") << "}}";
            if (!cache_path.empty()) {
                options << ",\"tmp_path\":\"" << json_escape(cache_path) << "\"";
            }
            options << "}";
            if (!candidate->set_config(options.str()) || !candidate->load()) {
                finish_with_error(callback, request_id, "MNN 模型加载失败，请检查文件完整性、后端配置和可用内存");
                return;
            }
            const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(
                std::chrono::steady_clock::now() - started);
            {
                std::lock_guard<std::mutex> lock(mutex_);
                llm_ = std::move(candidate);
                load_microseconds_ = elapsed.count();
                busy_ = false;
            }
            emit_event(callback, request_id, FK_MNN_EVENT_LOADED);
        }).detach();
        return true;
    }

    bool generate_async(
        int64_t request_id,
        ChatMessages messages,
        std::vector<MultimodalAttachment> attachments,
        int max_new_tokens,
        double temperature,
        double top_p,
        int top_k,
        int64_t timeout_milliseconds,
        FkMnnEventCallback callback) {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (busy_ || !llm_) {
                return false;
            }
            busy_ = true;
            active_request_ = request_id;
            cancel_requested_.store(false);
        }
        std::thread([
            this,
            request_id,
            messages = std::move(messages),
            attachments = std::move(attachments),
            max_new_tokens,
            temperature,
            top_p,
            top_k,
            timeout_milliseconds,
            callback]() mutable {
            Llm* llm = nullptr;
            {
                std::lock_guard<std::mutex> lock(mutex_);
                llm = llm_.get();
            }
            if (llm == nullptr) {
                finish_generation(callback, request_id, FK_MNN_EVENT_ERROR, "MNN 模型尚未加载");
                return;
            }
            std::ostringstream sampling;
            sampling << "{\"sampler_type\":\"mixed\",\"temperature\":" << temperature
                     << ",\"topP\":" << top_p << ",\"topK\":" << top_k
                     << ",\"timeout_ms\":" << timeout_milliseconds << "}";
            llm->set_config(sampling.str());
            std::string preparation_error;
            if (!prepare_multimodal_messages(messages, attachments, preparation_error)) {
                finish_generation(callback, request_id, FK_MNN_EVENT_ERROR, preparation_error);
                return;
            }

            int64_t request_vision_us = 0;
            int64_t request_audio_us = 0;
            float request_pixels_mp = 0.0f;
            float request_audio_input_s = 0.0f;
            if (attachments.empty()) {
                llm->response(messages, nullptr, nullptr, 0);
            } else {
                bool has_image = false;
                bool has_audio = false;
                for (const auto& attachment : attachments) {
                    has_image = has_image || is_image_mime(attachment.mime_type);
                    has_audio = has_audio || is_audio_mime(attachment.mime_type);
                }
                // MNN's text ChatMessages path owns prompt-cache prefix
                // reconciliation. The multimodal token path bypasses it, so
                // explicitly discard stale KV state before prefilling the full
                // templated conversation.
                llm->reset();
                const LlmContext* before = llm->getContext();
                const int64_t vision_before = before ? before->vision_us : 0;
                const int64_t audio_before = before ? before->audio_us : 0;
                const float pixels_before = before ? before->pixels_mp : 0.0f;
                const float audio_input_before = before ? before->audio_input_s : 0.0f;

                MultimodalPrompt multimodal_prompt;
                multimodal_prompt.prompt_template = llm->apply_chat_template(messages);
                auto input_ids = llm->tokenizer_encode(multimodal_prompt);
                const LlmContext* processed = llm->getContext();
                request_vision_us = processed ? processed->vision_us - vision_before : 0;
                request_audio_us = processed ? processed->audio_us - audio_before : 0;
                request_pixels_mp = processed ? processed->pixels_mp - pixels_before : 0.0f;
                request_audio_input_s = processed ? processed->audio_input_s - audio_input_before : 0.0f;
                if (has_image && request_pixels_mp <= 0.0f) {
                    finish_generation(
                        callback,
                        request_id,
                        FK_MNN_EVENT_ERROR,
                        "当前模型没有成功处理图片，请确认视觉模型文件完整且模型支持图片理解");
                    return;
                }
                if (has_audio && request_audio_input_s <= 0.0f) {
                    finish_generation(
                        callback,
                        request_id,
                        FK_MNN_EVENT_ERROR,
                        "当前模型没有成功处理音频，请确认音频模型文件完整且模型支持音频理解");
                    return;
                }
                if (input_ids.empty()) {
                    finish_generation(callback, request_id, FK_MNN_EVENT_ERROR, "多模态提示词编码失败");
                    return;
                }
                llm->response(input_ids, nullptr, nullptr, 0);
            }

            std::size_t emitted_bytes = 0;
            int generated_steps = 0;
            bool natural_end = false;
            while (!cancel_requested_.load() && generated_steps < max_new_tokens) {
                llm->generate(1);
                generated_steps++;
                const LlmContext* context = llm->getContext();
                if (context == nullptr) {
                    break;
                }
                const std::size_t complete_bytes =
                    complete_utf8_prefix_size(context->generate_str);
                if (complete_bytes > emitted_bytes) {
                    emit_event(
                        callback,
                        request_id,
                        FK_MNN_EVENT_TEXT_DELTA,
                        context->generate_str.substr(
                            emitted_bytes,
                            complete_bytes - emitted_bytes));
                    emitted_bytes = complete_bytes;
                }
                if (context->status == LlmStatus::NORMAL_FINISHED) {
                    natural_end = true;
                    break;
                }
                if (context->status == LlmStatus::TIMEOUT ||
                    context->status == LlmStatus::INTERNAL_ERROR) {
                    break;
                }
                if (context->status == LlmStatus::MAX_TOKENS_FINISHED &&
                    generated_steps < max_new_tokens) {
                    auto* mutable_context = const_cast<LlmContext*>(context);
                    mutable_context->status = LlmStatus::RUNNING;
                }
            }

            const LlmContext* context = llm->getContext();
            if (cancel_requested_.load()) {
                finish_generation(callback, request_id, FK_MNN_EVENT_CANCELED);
                return;
            }
            if (context != nullptr && context->status == LlmStatus::INTERNAL_ERROR) {
                finish_generation(callback, request_id, FK_MNN_EVENT_ERROR, "MNN 推理过程中发生内部错误");
                return;
            }
            if (context != nullptr && context->generate_str.size() != emitted_bytes) {
                finish_generation(
                    callback,
                    request_id,
                    FK_MNN_EVENT_ERROR,
                    "MNN 输出包含未完成的 UTF-8 字符");
                return;
            }
            const char* reason = natural_end ? "completed" :
                (context != nullptr && context->status == LlmStatus::TIMEOUT ? "timeout" : "maxTokens");
            std::ostringstream metrics;
            metrics << "{\"reason\":\"" << reason << "\""
                    << ",\"promptTokens\":" << (context ? context->prompt_len : 0)
                    << ",\"generatedTokens\":" << (context ? context->gen_seq_len : generated_steps)
                    << ",\"loadUs\":" << load_microseconds_
                    << ",\"prefillUs\":" << (context ? context->prefill_us : 0)
                    << ",\"decodeUs\":" << (context ? context->decode_us : 0)
                    << ",\"visionUs\":" << request_vision_us
                    << ",\"audioUs\":" << request_audio_us
                    << ",\"imageMegapixels\":" << request_pixels_mp
                    << ",\"audioInputSeconds\":" << request_audio_input_s
                    << "}";
            finish_generation(callback, request_id, FK_MNN_EVENT_COMPLETED, metrics.str());
        }).detach();
        return true;
    }

    bool cancel(int64_t request_id) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!busy_ || active_request_ != request_id) {
            return false;
        }
        cancel_requested_.store(true);
        return true;
    }

    bool unload_async(int64_t request_id, FkMnnEventCallback callback) {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (busy_) {
                return false;
            }
            busy_ = true;
        }
        std::thread([this, request_id, callback]() {
            {
                std::lock_guard<std::mutex> lock(mutex_);
                llm_.reset();
                load_microseconds_ = 0;
                busy_ = false;
                active_request_ = 0;
            }
            emit_event(callback, request_id, FK_MNN_EVENT_UNLOADED);
        }).detach();
        return true;
    }

private:
    void finish_with_error(
        FkMnnEventCallback callback,
        int64_t request_id,
        const std::string& message) {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            busy_ = false;
        }
        emit_event(callback, request_id, FK_MNN_EVENT_ERROR, message);
    }

    void finish_generation(
        FkMnnEventCallback callback,
        int64_t request_id,
        int32_t event_type,
        const std::string& data = {}) {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            busy_ = false;
            active_request_ = 0;
        }
        emit_event(callback, request_id, event_type, data);
    }

    std::mutex mutex_;
    std::unique_ptr<Llm> llm_;
    std::atomic<bool> cancel_requested_{false};
    bool busy_ = false;
    int64_t active_request_ = 0;
    int64_t load_microseconds_ = 0;
};

Runtime& runtime() {
    static Runtime instance;
    return instance;
}

#endif

}  // namespace

extern "C" {

int32_t fk_mnn_is_available(void) {
#if defined(FKNOTES_MNN_RUNTIME)
    return 1;
#else
    return 0;
#endif
}

const char* fk_mnn_runtime_version(void) {
    return kRuntimeVersion;
}

int32_t fk_mnn_load_async(
    int64_t request_id,
    const char* config_path,
    const char* cache_path,
    const char* backend,
    int32_t threads,
    int32_t context_tokens,
    int32_t enable_thinking,
    int32_t enable_prompt_cache,
    FkMnnEventCallback callback) {
#if defined(FKNOTES_MNN_RUNTIME)
    if (config_path == nullptr || backend == nullptr || callback == nullptr ||
        threads <= 0 || context_tokens <= 0) {
        return 0;
    }
    return runtime().load_async(
        request_id,
        config_path,
        cache_path == nullptr ? "" : cache_path,
        backend,
        threads,
        context_tokens,
        enable_thinking != 0,
        enable_prompt_cache != 0,
        callback) ? 1 : 0;
#else
    (void)request_id; (void)config_path; (void)cache_path; (void)backend;
    (void)threads; (void)context_tokens; (void)enable_thinking;
    (void)enable_prompt_cache; (void)callback;
    return 0;
#endif
}

int32_t fk_mnn_generate_async(
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
    FkMnnEventCallback callback) {
#if defined(FKNOTES_MNN_RUNTIME)
    if (roles == nullptr || contents == nullptr || message_count <= 0 ||
        attachment_count < 0 ||
        (attachment_count > 0 &&
         (attachment_paths == nullptr || attachment_mime_types == nullptr ||
          attachment_message_indexes == nullptr)) ||
        max_new_tokens <= 0 || callback == nullptr) {
        return 0;
    }
    ChatMessages messages;
    messages.reserve(static_cast<std::size_t>(message_count));
    for (int32_t index = 0; index < message_count; index++) {
        if (roles[index] == nullptr || contents[index] == nullptr) {
            return 0;
        }
        messages.emplace_back(roles[index], contents[index]);
    }
    std::vector<MultimodalAttachment> attachments;
    attachments.reserve(static_cast<std::size_t>(attachment_count));
    for (int32_t index = 0; index < attachment_count; index++) {
        if (attachment_paths[index] == nullptr || attachment_mime_types[index] == nullptr) {
            return 0;
        }
        std::string mime_type(attachment_mime_types[index]);
        std::transform(
            mime_type.begin(),
            mime_type.end(),
            mime_type.begin(),
            [](unsigned char character) { return static_cast<char>(std::tolower(character)); });
        attachments.push_back({
            attachment_message_indexes[index],
            attachment_paths[index],
            std::move(mime_type),
        });
    }
    return runtime().generate_async(
        request_id,
        std::move(messages),
        std::move(attachments),
        max_new_tokens,
        temperature,
        top_p,
        top_k,
        timeout_milliseconds,
        callback) ? 1 : 0;
#else
    (void)request_id; (void)roles; (void)contents; (void)message_count;
    (void)attachment_paths; (void)attachment_mime_types;
    (void)attachment_message_indexes; (void)attachment_count;
    (void)max_new_tokens; (void)temperature; (void)top_p; (void)top_k;
    (void)timeout_milliseconds; (void)callback;
    return 0;
#endif
}

int32_t fk_mnn_cancel(int64_t request_id) {
#if defined(FKNOTES_MNN_RUNTIME)
    return runtime().cancel(request_id) ? 1 : 0;
#else
    (void)request_id;
    return 0;
#endif
}

int32_t fk_mnn_unload_async(
    int64_t request_id,
    FkMnnEventCallback callback) {
#if defined(FKNOTES_MNN_RUNTIME)
    if (callback == nullptr) {
        return 0;
    }
    return runtime().unload_async(request_id, callback) ? 1 : 0;
#else
    (void)request_id; (void)callback;
    return 0;
#endif
}

void fk_mnn_free(void* data) {
    std::free(data);
}

}  // extern "C"
