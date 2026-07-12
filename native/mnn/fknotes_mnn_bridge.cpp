#include "fknotes_mnn_bridge.h"

#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>
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

#if defined(FKNOTES_MNN_RUNTIME)

using MNN::Transformer::ChatMessage;
using MNN::Transformer::ChatMessages;
using MNN::Transformer::Llm;
using MNN::Transformer::LlmContext;
using MNN::Transformer::LlmStatus;

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
            max_new_tokens,
            temperature,
            top_p,
            top_k,
            timeout_milliseconds,
            callback]() {
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
            llm->response(messages, nullptr, nullptr, 0);

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
                if (context->generate_str.size() > emitted_bytes) {
                    emit_event(
                        callback,
                        request_id,
                        FK_MNN_EVENT_TEXT_DELTA,
                        context->generate_str.substr(emitted_bytes));
                    emitted_bytes = context->generate_str.size();
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
            const char* reason = natural_end ? "completed" :
                (context != nullptr && context->status == LlmStatus::TIMEOUT ? "timeout" : "maxTokens");
            std::ostringstream metrics;
            metrics << "{\"reason\":\"" << reason << "\""
                    << ",\"promptTokens\":" << (context ? context->prompt_len : 0)
                    << ",\"generatedTokens\":" << (context ? context->gen_seq_len : generated_steps)
                    << ",\"loadUs\":" << load_microseconds_
                    << ",\"prefillUs\":" << (context ? context->prefill_us : 0)
                    << ",\"decodeUs\":" << (context ? context->decode_us : 0)
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
    int32_t max_new_tokens,
    double temperature,
    double top_p,
    int32_t top_k,
    int64_t timeout_milliseconds,
    FkMnnEventCallback callback) {
#if defined(FKNOTES_MNN_RUNTIME)
    if (roles == nullptr || contents == nullptr || message_count <= 0 ||
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
    return runtime().generate_async(
        request_id,
        std::move(messages),
        max_new_tokens,
        temperature,
        top_p,
        top_k,
        timeout_milliseconds,
        callback) ? 1 : 0;
#else
    (void)request_id; (void)roles; (void)contents; (void)message_count;
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
