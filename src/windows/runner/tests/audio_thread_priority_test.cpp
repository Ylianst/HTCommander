// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
// Standalone: cl /nologo /std:c++17 /EHsc /W4 /WX audio_thread_priority_test.cpp
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <avrt.h>

#include <cstdio>
#include <cstdlib>
#include <cwchar>

#define CHECK(condition)                                                 \
  do {                                                                 \
    if (!(condition)) {                                                \
      std::fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #condition); \
      std::abort();                                                    \
    }                                                                  \
  } while (false)

namespace {

bool fail_registration = false;
bool fail_priority = false;
int registrations = 0;
int boosts = 0;
int reverts = 0;
int task_tag = 0;

HANDLE WINAPI RegisterAudio(LPCWSTR name, LPDWORD index) {
  CHECK(std::wcscmp(name, L"Audio") == 0);
  CHECK(*index == 0);
  ++registrations;
  if (fail_registration) {
    SetLastError(ERROR_SERVICE_NOT_ACTIVE);
    return nullptr;
  }
  *index = 1;
  return &task_tag;
}

BOOL WINAPI BoostAudio(HANDLE task, AVRT_PRIORITY priority) {
  CHECK(task == &task_tag);
  CHECK(priority == AVRT_PRIORITY_HIGH);
  ++boosts;
  if (fail_priority) {
    SetLastError(ERROR_ACCESS_DENIED);
    return FALSE;
  }
  return TRUE;
}

BOOL WINAPI RevertAudio(HANDLE task) {
  CHECK(task == &task_tag);
  ++reverts;
  return TRUE;
}

}  // namespace

#define AvSetMmThreadCharacteristicsW RegisterAudio
#define AvSetMmThreadPriority BoostAudio
#define AvRevertMmThreadCharacteristics RevertAudio
#include "..\audio_thread_priority.h"
#undef AvSetMmThreadCharacteristicsW
#undef AvSetMmThreadPriority
#undef AvRevertMmThreadCharacteristics

int main() {
  const int original = GetThreadPriority(GetCurrentThread());
  CHECK(original != THREAD_PRIORITY_ERROR_RETURN);
  {
    AudioThreadPriority priority(false);
    CHECK(registrations == 0);
    CHECK(GetThreadPriority(GetCurrentThread()) == original);
  }
  {
    AudioThreadPriority priority;
    CHECK(registrations == 1 && boosts == 1 && reverts == 0);
  }
  CHECK(reverts == 1);

  fail_registration = true;
  {
    AudioThreadPriority priority;
    CHECK(registrations == 2 && boosts == 1);
    CHECK(GetThreadPriority(GetCurrentThread()) >= THREAD_PRIORITY_ABOVE_NORMAL);
  }
  CHECK(reverts == 1);
  CHECK(GetThreadPriority(GetCurrentThread()) == original);

  fail_registration = false;
  fail_priority = true;
  {
    AudioThreadPriority priority;
    CHECK(registrations == 3 && boosts == 2);
  }
  CHECK(reverts == 2);
  CHECK(GetThreadPriority(GetCurrentThread()) == original);
  std::puts("audio_thread_priority_test: passed");
  return 0;
}
