// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
// Standalone test from an MSVC developer prompt at the repository root:
// cl /nologo /std:c++17 /EHsc /W4 /WX ^
//   src\windows\runner\tests\native_thread_group_test.cpp ^
//   /Fe:native_thread_group_test.exe
#include "..\native_thread_group.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <future>

#define CHECK(condition)                                                  \
  do {                                                                    \
    if (!(condition)) {                                                   \
      std::fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #condition);   \
      std::abort();                                                       \
    }                                                                     \
  } while (false)

int main() {
  using namespace std::chrono_literals;
  // The reader is no longer in the connection map, and a pending connect may
  // finish after shutdown starts. Neither may escape ownership at teardown.
  NativeThreadGroup workers;
  auto connection = std::make_shared<int>(42);
  std::weak_ptr<int> retired = connection;
  std::promise<void> release;
  auto gate = release.get_future().share();
  std::promise<void> entered;
  auto started = entered.get_future();
  std::atomic<bool> replied{false};
  CHECK(workers.Start([&, gate, connection] {
    entered.set_value();
    gate.wait();
    CHECK(*connection == 42);
    CHECK(!workers.Start([] { std::abort(); }));
    replied.store(true);
  }));
  CHECK(started.wait_for(3s) == std::future_status::ready);
  connection.reset();
  workers.Close();
  CHECK(!workers.Start([] { std::abort(); }));
  std::promise<void> joining;
  auto join_started = joining.get_future();
  auto joined = std::async(std::launch::async, [&] {
    joining.set_value();
    workers.Join();
  });
  CHECK(join_started.wait_for(3s) == std::future_status::ready);
  CHECK(joined.wait_for(20ms) == std::future_status::timeout);
  CHECK(!retired.expired());
  CHECK(!replied.load());
  release.set_value();
  CHECK(joined.wait_for(3s) == std::future_status::ready);
  joined.get();
  CHECK(retired.expired());
  CHECK(replied.load());

  // Completed callbacks are reaped without waiting for still-live readers.
  NativeThreadGroup reusable;
  std::atomic<int> completed{0};
  for (int i = 0; i < 200; ++i) {
    CHECK(reusable.Start([&] { completed.fetch_add(1); }));
  }
  reusable.Close();
  reusable.Join();
  CHECK(completed.load() == 200);
  std::puts("native_thread_group_test: passed");
}
