// Host test for platform/engine_log.h's non-Android path (the one a desktop front-end uses).
// On Android the macros are the __android_log_print calls themselves and there is nothing to test.
#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

#include "platform/engine_log.h"

static int g_checks = 0, g_failed = 0;
#define CHECK(cond) do { g_checks++; if (!(cond)) { g_failed++; std::printf("  FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); } } while (0)

struct Msg { int level; std::string tag, text; };
static std::vector<Msg> g_msgs;
static void collect(int level, const char* tag, const char* message) { g_msgs.push_back({level, tag, message}); }
static std::atomic<int> g_threadMsgs{0}, g_threadMsgs2{0};
static void count(int, const char*, const char*) { ++g_threadMsgs; }
static void count2(int, const char*, const char*) { ++g_threadMsgs2; }

// The way engine files use it (see e.g. session/session_guard.cpp).
#define LOGI(...) ENGINE_LOG_INFO("TestTag", __VA_ARGS__)

int main() {
#if defined(__ANDROID__)
    std::printf("engine_log_test: nothing to do on Android\n");
    return 0;
#else
    // no sink installed: logging is a no-op, never a crash
    engineLogSetSink(nullptr);
    LOGI("nobody is listening %d", 1);
    ENGINE_LOG_ERROR("T", "still fine");

    // a sink receives level, tag and the formatted message
    engineLogSetSink(&collect);
    LOGI("unlock %s: vol=%d fr=%u", "ok", 3, 7u);
    ENGINE_LOG_WARN("VaultExplorer_FatIO", "%s failed: vol=%d", "mount", 2);
    ENGINE_LOG_ERROR("E", "bad");
    LOGI("plain text, no arguments");
    CHECK(g_msgs.size() == 4);
    CHECK(g_msgs[0].level == ENGINE_LOG_LEVEL_INFO && g_msgs[0].tag == "TestTag" && g_msgs[0].text == "unlock ok: vol=3 fr=7");
    CHECK(g_msgs[1].level == ENGINE_LOG_LEVEL_WARN && g_msgs[1].tag == "VaultExplorer_FatIO" && g_msgs[1].text == "mount failed: vol=2");
    CHECK(g_msgs[2].level == ENGINE_LOG_LEVEL_ERROR && g_msgs[2].text == "bad");
    CHECK(g_msgs[3].text == "plain text, no arguments");
    CHECK(ENGINE_LOG_LEVEL_INFO < ENGINE_LOG_LEVEL_WARN && ENGINE_LOG_LEVEL_WARN < ENGINE_LOG_LEVEL_ERROR);

    // an oversized message is truncated to the buffer, never overflowed
    g_msgs.clear();
    const std::string big(5000, 'x');
    LOGI("%s", big.c_str());
    CHECK(g_msgs.size() == 1 && g_msgs[0].text.size() == 1023 && g_msgs[0].text.find_first_not_of('x') == std::string::npos);

    // replacing and removing the sink
    g_msgs.clear();
    engineLogSetSink(nullptr);
    LOGI("dropped");
    CHECK(g_msgs.empty());

    // installing a sink while other threads log must be safe (the slot is atomic)
    engineLogSetSink(&count);
    std::vector<std::thread> ts;
    for (int t = 0; t < 4; ++t) ts.emplace_back([] { for (int i = 0; i < 2000; ++i) LOGI("t %d", i); });
    for (int i = 0; i < 200; ++i) { engineLogSetSink(&count); engineLogSetSink(&count2); engineLogSetSink(&count); }
    for (auto& t : ts) t.join();
    engineLogSetSink(nullptr);
    // every message went to exactly one of the two sinks (none lost, none duplicated)
    CHECK(g_threadMsgs.load() + g_threadMsgs2.load() == 4 * 2000);

    std::printf("\n%d checks, %d failed\n", g_checks, g_failed);
    return g_failed ? 1 : 0;
#endif
}
