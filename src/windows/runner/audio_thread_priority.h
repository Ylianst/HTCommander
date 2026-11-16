// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#pragma once

#include <windows.h>
#include <avrt.h>

#include <cstdio>

class AudioThreadPriority {
 public:
  explicit AudioThreadPriority(bool enabled = true) {
    if (!enabled) return;
    DWORD task_index = 0;
    task_ = AvSetMmThreadCharacteristicsW(L"Audio", &task_index);
    if (task_) {
      if (!AvSetMmThreadPriority(task_, AVRT_PRIORITY_HIGH)) {
        Report("AvSetMmThreadPriority", GetLastError());
      }
      return;
    }

    Report("AvSetMmThreadCharacteristicsW (using thread-priority fallback)",
           GetLastError());
    previous_priority_ = GetThreadPriority(GetCurrentThread());
    if (previous_priority_ == THREAD_PRIORITY_ERROR_RETURN) {
      Report("GetThreadPriority", GetLastError());
    } else if (previous_priority_ < THREAD_PRIORITY_ABOVE_NORMAL) {
      restore_priority_ =
          SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_ABOVE_NORMAL) !=
          FALSE;
      if (!restore_priority_) Report("SetThreadPriority", GetLastError());
    }
  }

  ~AudioThreadPriority() {
    if (task_ && !AvRevertMmThreadCharacteristics(task_)) {
      Report("AvRevertMmThreadCharacteristics", GetLastError());
    }
    if (restore_priority_ &&
        !SetThreadPriority(GetCurrentThread(), previous_priority_)) {
      Report("SetThreadPriority (restore)", GetLastError());
    }
  }

  AudioThreadPriority(const AudioThreadPriority&) = delete;
  AudioThreadPriority& operator=(const AudioThreadPriority&) = delete;

 private:
  static void Report(const char* operation, DWORD error) {
    char message[256] = {};
    std::snprintf(message, sizeof(message),
                  "[AudioThreadPriority] %s failed (%lu)\n", operation,
                  static_cast<unsigned long>(error));
    OutputDebugStringA(message);
    std::fputs(message, stderr);
  }

  HANDLE task_ = nullptr;
  int previous_priority_ = THREAD_PRIORITY_NORMAL;
  bool restore_priority_ = false;
};
