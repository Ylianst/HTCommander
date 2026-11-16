// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
//
// Standalone deterministic WinMM substitute; no Flutter build/audio hardware.
// From an MSVC developer prompt at the repository root:
// cl /nologo /std:c++17 /EHsc /W4 /WX /DNOMINMAX /D_WINMM_ ^
//   src\windows\runner\native_pcm_output.cpp ^
//   src\windows\runner\tests\native_pcm_output_test.cpp ^
//   /Fe:native_pcm_output_test.exe /link user32.lib
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <mmsystem.h>

#include "..\native_pcm_output.h"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <limits>
#include <mutex>
#include <thread>
#include <vector>

#define CHECK(condition)                                                    \
  do {                                                                    \
    if (!(condition)) {                                                   \
      std::fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #condition);   \
      std::abort();                                                       \
    }                                                                     \
  } while (false)

namespace {

struct FakeDevice {
  HANDLE completion;
  std::vector<WAVEHDR*> headers;
};

std::mutex driver_mutex;
FakeDevice* current_device = nullptr;
DWORD driver_thread = 0;
const DWORD platform_thread = GetCurrentThreadId();
std::atomic<bool> fail_open{false};
std::atomic<bool> fail_prepare{false};
std::atomic<bool> fail_write{false};
std::atomic<bool> fail_reset{false};
std::atomic<bool> fail_close{false};
std::atomic<bool> fail_selected_device{false};
int selected_attempts = 0;

void CheckWorker() {
  const DWORD thread = GetCurrentThreadId();
  CHECK(thread != platform_thread);
  if (driver_thread == 0) driver_thread = thread;
  CHECK(driver_thread == thread);
}

FakeDevice* Device(HWAVEOUT handle) {
  CHECK(current_device != nullptr);
  CHECK(handle == reinterpret_cast<HWAVEOUT>(current_device));
  return current_device;
}

size_t SubmittedBuffers() {
  std::lock_guard<std::mutex> lock(driver_mutex);
  return current_device ? current_device->headers.size() : 0;
}

template <typename Predicate>
bool WaitFor(Predicate predicate) {
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(3);
  while (!predicate()) {
    if (std::chrono::steady_clock::now() >= deadline) return false;
    Sleep(1);
  }
  return true;
}

void CompleteAll() {
  CHECK(WaitFor([] { return SubmittedBuffers() != 0; }));
  std::lock_guard<std::mutex> lock(driver_mutex);
  CHECK(current_device != nullptr);
  for (auto* header : current_device->headers) {
    header->dwFlags |= WHDR_DONE;
    header->dwFlags &= ~WHDR_INQUEUE;
  }
  SetEvent(current_device->completion);
}

}  // namespace

extern "C" {

UINT WINAPI waveOutGetNumDevs() {
  CheckWorker();
  return 2;
}

MMRESULT WINAPI waveOutGetErrorTextA(MMRESULT, LPSTR text, UINT length) {
  CheckWorker();
  if (length != 0) text[0] = '\0';
  return MMSYSERR_NOERROR;
}

MMRESULT WINAPI waveOutOpen(LPHWAVEOUT handle, UINT index,
                            LPCWAVEFORMATEX format, DWORD_PTR callback,
                            DWORD_PTR instance, DWORD flags) {
  CheckWorker();
  std::lock_guard<std::mutex> lock(driver_mutex);
  CHECK(current_device == nullptr);  // Never open a second device.
  CHECK(flags == CALLBACK_EVENT);
  CHECK(instance == 0);
  CHECK(format->wFormatTag == WAVE_FORMAT_PCM);
  CHECK(format->wBitsPerSample == 16);
  if (index != WAVE_MAPPER) ++selected_attempts;
  if (fail_open || (index != WAVE_MAPPER && fail_selected_device)) {
    return MMSYSERR_BADDEVICEID;
  }
  current_device = new FakeDevice{reinterpret_cast<HANDLE>(callback), {}};
  *handle = reinterpret_cast<HWAVEOUT>(current_device);
  SetEvent(current_device->completion);  // Also exercise WOM_OPEN wakeups.
  return MMSYSERR_NOERROR;
}

MMRESULT WINAPI waveOutPrepareHeader(HWAVEOUT handle, LPWAVEHDR header,
                                     UINT size) {
  CheckWorker();
  std::lock_guard<std::mutex> lock(driver_mutex);
  Device(handle);
  CHECK(size == sizeof(WAVEHDR));
  if (fail_prepare) return MMSYSERR_NOMEM;
  CHECK(header->lpData != nullptr);
  header->dwFlags |= WHDR_PREPARED;
  return MMSYSERR_NOERROR;
}

MMRESULT WINAPI waveOutWrite(HWAVEOUT handle, LPWAVEHDR header, UINT size) {
  CheckWorker();
  std::lock_guard<std::mutex> lock(driver_mutex);
  auto* device = Device(handle);
  CHECK(size == sizeof(WAVEHDR));
  CHECK((header->dwFlags & WHDR_PREPARED) != 0);
  if (fail_write) return MMSYSERR_ERROR;
  header->dwFlags |= WHDR_INQUEUE;
  device->headers.push_back(header);
  return MMSYSERR_NOERROR;
}

MMRESULT WINAPI waveOutUnprepareHeader(HWAVEOUT handle, LPWAVEHDR header,
                                       UINT size) {
  CheckWorker();
  std::lock_guard<std::mutex> lock(driver_mutex);
  auto* device = Device(handle);
  CHECK(size == sizeof(WAVEHDR));
  if ((header->dwFlags & WHDR_INQUEUE) != 0) return WAVERR_STILLPLAYING;
  header->dwFlags &= ~WHDR_PREPARED;
  for (auto it = device->headers.begin(); it != device->headers.end(); ++it) {
    if (*it == header) {
      device->headers.erase(it);
      break;
    }
  }
  return MMSYSERR_NOERROR;
}

MMRESULT WINAPI waveOutReset(HWAVEOUT handle) {
  CheckWorker();
  std::lock_guard<std::mutex> lock(driver_mutex);
  auto* device = Device(handle);
  if (fail_reset) return MMSYSERR_ERROR;
  for (auto* header : device->headers) {
    header->dwFlags |= WHDR_DONE;
    header->dwFlags &= ~WHDR_INQUEUE;
  }
  SetEvent(device->completion);
  return MMSYSERR_NOERROR;
}

MMRESULT WINAPI waveOutClose(HWAVEOUT handle) {
  CheckWorker();
  std::lock_guard<std::mutex> lock(driver_mutex);
  auto* device = Device(handle);
  CHECK(device->headers.empty());
  if (fail_close) return MMSYSERR_ERROR;
  SetEvent(device->completion);  // Stale close wake must not affect next setup.
  delete device;
  current_device = nullptr;
  return MMSYSERR_NOERROR;
}

}  // extern "C"

int main() {
  {
    NativePcmOutput output;
    std::vector<uint8_t> mono(1280, 0);  // 20 ms silence at 32000 Hz.
    std::vector<int16_t> radio(640, 0);
    CHECK(!output.Feed(mono.data(), mono.size()));
    CHECK(!output.FeedRadio(radio.data(), radio.size()));
    CHECK(!output.Setup(0, 1, ""));
    CHECK(!output.Setup(32000, 32768, ""));
    CHECK(!output.Setup(2147483647, 2, ""));
    CHECK(output.Setup(48000, 1, ""));
    CHECK(!output.FeedRadio(radio.data(), radio.size()));
    CHECK(output.buffered_frames() == 0);
    CHECK(output.Setup(32000, 2, ""));
    CHECK(!output.FeedRadio(radio.data(), radio.size()));
    CHECK(output.buffered_frames() == 0);
    CHECK(output.Setup(32000, 1, ""));
    CHECK(output.IsRadioFormat());
    CHECK(!output.Feed(nullptr, mono.size()));
    CHECK(!output.Feed(mono.data(), 0));
    CHECK(!output.Feed(mono.data(), 3));
    CHECK(!output.FeedRadio(nullptr, radio.size()));
    CHECK(!output.FeedRadio(radio.data(), 0));
    CHECK(!output.FeedRadio(radio.data(),
                            (std::numeric_limits<size_t>::max)()));

    std::atomic<int> notifications{0};
    std::atomic<int64_t> remaining{-1};
    output.SetFeedCallback([&](int64_t frames) {
      CHECK(GetCurrentThreadId() != platform_thread);
      remaining.store(frames);
      notifications.fetch_add(1);
    });
    CHECK(output.FeedRadio(radio.data(), radio.size()));
    CHECK(output.buffered_frames() == 640);
    CompleteAll();
    // Deliberately never pump platform messages anywhere in this test.
    CHECK(WaitFor([&] { return notifications.load() == 1; }));
    CHECK(remaining.load() == 0);
    CHECK(output.buffered_frames() == 0);
    CHECK(output.stats().underruns == 1);

    std::vector<uint8_t> full_queue(51200, 0);
    CHECK(output.Feed(full_queue.data(), full_queue.size()));
    CHECK(!output.Feed(mono.data(), 2));
    CHECK(output.buffered_frames() == 25600);
    CHECK(output.stats().overflows == 1);
    output.Release();
    CHECK(output.buffered_frames() == 0);
    CHECK(!output.IsRadioFormat());

    CHECK(output.Setup(32000, 1, "invalid"));
    CHECK(output.Feed(mono.data(), mono.size()));
    CHECK(output.Setup(48000, 2, "1"));
    CHECK(!output.IsRadioFormat());
    CHECK(output.buffered_frames() == 0);
    CHECK(!output.Feed(mono.data(), 2));  // Stereo frame alignment.
    CHECK(output.Feed(mono.data(), mono.size()));
    CHECK(output.buffered_frames() == 320);
    CompleteAll();
    CHECK(WaitFor([&] { return notifications.load() == 2; }));
    CHECK(output.buffered_frames() == 0);

    fail_selected_device = true;
    CHECK(output.Setup(32000, 1, "1"));  // Selected-device fallback.
    fail_selected_device = false;
    CHECK(selected_attempts == 2);
    fail_open = true;
    CHECK(!output.Setup(32000, 1, ""));
    CHECK(!output.IsRadioFormat());
    fail_open = false;
    CHECK(output.Setup(32000, 1, ""));
    fail_prepare = true;
    uint64_t previous_errors = output.error_count();
    CHECK(output.Feed(mono.data(), mono.size()));
    CHECK(WaitFor([&] {
      return output.error_count() > previous_errors &&
             output.buffered_frames() == 0;
    }));
    CHECK(output.buffered_frames() == 0);
    fail_prepare = false;
    fail_write = true;
    previous_errors = output.error_count();
    CHECK(output.Feed(mono.data(), mono.size()));
    CHECK(WaitFor([&] {
      return output.error_count() > previous_errors &&
             output.buffered_frames() == 0;
    }));
    CHECK(output.buffered_frames() == 0);
    fail_write = false;
    CHECK(output.Feed(mono.data(), mono.size()));
    CHECK(WaitFor([] { return SubmittedBuffers() == 1; }));
    fail_reset = true;
    output.Release();  // Failed reset must retain still-playing header storage.
    CHECK(SubmittedBuffers() == 1);
    CHECK(output.buffered_frames() == 0);  // Closed generation isn't observable.
    CHECK(!output.Feed(mono.data(), mono.size()));
    CHECK(!output.Setup(48000, 2, ""));
    fail_reset = false;
    output.Release();
    CHECK(output.buffered_frames() == 0);
    CHECK(output.Setup(32000, 1, ""));
    fail_close = true;
    CHECK(!output.Setup(32000, 1, ""));
    fail_close = false;
    output.Release();
    CHECK(output.Setup(32000, 1, ""));

    // Concurrent callers cannot exceed the latency cap.
    output.SetFeedCallback(nullptr);
    std::atomic<int> accepted{0};
    std::vector<std::thread> producers;
    for (int i = 0; i < 8; ++i) {
      producers.emplace_back([&] {
        for (int j = 0; j < 10; ++j) {
          const bool fed = j % 2 == 0
                               ? output.FeedRadio(radio.data(), radio.size())
                               : output.Feed(mono.data(), mono.size());
          if (fed) accepted.fetch_add(1);
        }
      });
    }
    for (auto& producer : producers) producer.join();
    CHECK(accepted.load() == 40);
    CHECK(output.buffered_frames() == 25600);
    CHECK(output.stats().overflows == 41);
    CompleteAll();
    CHECK(WaitFor([&] { return output.buffered_frames() == 0; }));

    HANDLE entered = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    HANDLE unblock = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    CHECK(entered != nullptr && unblock != nullptr);
    output.SetFeedCallback([&](int64_t) {
      SetEvent(entered);
      CHECK(WaitForSingleObject(unblock, 3000) == WAIT_OBJECT_0);
    });
    CHECK(output.Feed(mono.data(), mono.size()));
    CompleteAll();
    CHECK(WaitForSingleObject(entered, 3000) == WAIT_OBJECT_0);
    std::atomic<bool> clearing{false};
    std::atomic<bool> detached{false};
    std::thread detach([&] {
      clearing.store(true);
      output.SetFeedCallback(nullptr);
      detached.store(true);
    });
    CHECK(WaitFor([&] { return clearing.load(); }));
    Sleep(10);
    CHECK(!detached.load());
    // Feed must not wait for a worker blocked in an observational callback.
    CHECK(output.Feed(mono.data(), mono.size()));
    CHECK(output.buffered_frames() == 640);
    SetEvent(unblock);
    detach.join();
    CHECK(detached.load());
    CloseHandle(entered);
    CloseHandle(unblock);
    CompleteAll();
    CHECK(WaitFor([&] { return output.buffered_frames() == 0; }));

    // Reconfigure immediately revokes the old format, even while the worker is
    // busy; no old accepted radio payload may survive the reconfiguration.
    entered = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    unblock = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    CHECK(entered != nullptr && unblock != nullptr);
    output.SetFeedCallback([&](int64_t) {
      SetEvent(entered);
      CHECK(WaitForSingleObject(unblock, 3000) == WAIT_OBJECT_0);
    });
    CHECK(output.FeedRadio(radio.data(), radio.size()));
    CompleteAll();
    CHECK(WaitForSingleObject(entered, 3000) == WAIT_OBJECT_0);
    CHECK(output.FeedRadio(radio.data(), radio.size()));
    std::atomic<bool> configured{false};
    std::thread configure([&] {
      CHECK(output.Setup(48000, 2, ""));
      configured.store(true);
    });
    CHECK(WaitFor([&] { return !output.IsRadioFormat(); }));
    CHECK(!configured.load());
    CHECK(!output.FeedRadio(radio.data(), radio.size()));
    SetEvent(unblock);
    configure.join();
    CHECK(output.buffered_frames() == 0);
    CHECK(SubmittedBuffers() == 0);
    CHECK(!output.FeedRadio(radio.data(), radio.size()));
    output.SetFeedCallback(nullptr);
    CloseHandle(entered);
    CloseHandle(unblock);
    CHECK(output.Setup(32000, 1, ""));

    // A callback can reenter a public API without deadlocking the worker.
    output.SetFeedCallback([&](int64_t) { output.Release(); });
    CHECK(output.Feed(mono.data(), mono.size()));
    CompleteAll();
    CHECK(WaitFor([&] { return !output.IsRadioFormat(); }));
    output.SetFeedCallback(nullptr);

    // Destruction with active buffers resets/unprepares them on the worker.
    CHECK(output.Setup(32000, 1, ""));
    CHECK(output.Feed(mono.data(), mono.size()));
    CHECK(WaitFor([] { return SubmittedBuffers() == 1; }));
  }
  CHECK(current_device == nullptr);
  std::puts("native_pcm_output_test: passed");
  return 0;
}
