// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <mmsystem.h>

#include "native_pcm_output.h"

#include <atomic>
#include <cstdio>
#include <deque>
#include <future>
#include <limits>
#include <list>
#include <mutex>
#include <thread>
#include <utility>
#include <vector>

namespace {

void Log(const std::string& message) {
  const std::string line = "[NativePcmOutput] " + message + "\n";
  OutputDebugStringA(line.c_str());
  std::fputs(line.c_str(), stderr);
}

void LogWaveError(const char* operation, MMRESULT error) {
  char text[MAXERRORLENGTH] = {};
  waveOutGetErrorTextA(error, text, MAXERRORLENGTH);
  Log(std::string(operation) + " failed (" + std::to_string(error) +
      "): " + text);
}

}  // namespace

struct NativePcmOutput::Impl {
  struct Buffer {
    WAVEHDR header = {};
    std::vector<uint8_t> bytes;
    int64_t frames = 0;
    uint64_t generation = 0;
    bool radio = false;
  };

  struct Command {
    std::function<void()> run;
    bool playback = false;
  };

  HANDLE wake = nullptr;
  HANDLE completion = nullptr;
  std::thread worker;
  std::mutex commands_mutex;
  std::deque<Command> commands;
  // Admission and command ordering share one short-held lock. No driver work
  // happens under it, so Bluetooth reader feeds never wait for the worker.
  bool accepting = false;
  int admitted_rate = 0;
  int admitted_frame_bytes = 0;
  uint64_t generation = 0;
  std::atomic<int64_t> queued_frames{0};
  std::atomic<uint64_t> underruns{0};
  std::atomic<uint64_t> overflows{0};
  std::atomic<uint64_t> errors{0};
  int64_t queued_radio_frames = 0;
  int64_t peak_buffered_ms = 0;
  uint64_t catchups = 0;
  uint64_t discarded_frames = 0;
  std::atomic<bool> radio_format{false};

  // Worker-only state.
  HWAVEOUT device = nullptr;
  bool open = false;
  bool stopping = false;
  std::list<std::shared_ptr<Buffer>> buffers;
  std::function<void(int64_t)> callback;

  Impl() {
    wake = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    completion = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!wake || !completion) {
      errors.fetch_add(1);
      Log("CreateEvent failed: " + std::to_string(GetLastError()));
      return;
    }
    try {
      worker = std::thread([this] { Run(); });
    } catch (const std::exception& error) {
      errors.fetch_add(1);
      Log(std::string("Cannot start output worker: ") + error.what());
    }
  }

  ~Impl() {
    if (worker.joinable()) {
      Invalidate();
      Invoke([this] {
        callback = nullptr;
        CloseDevice();
        stopping = true;
        return true;
      });
      worker.join();
    }
    if (wake) CloseHandle(wake);
    if (device) {
      // A broken driver refused reset/unprepare/close. Never free memory or the
      // callback event while that driver can still access them.
      Log("Driver refused teardown; retaining device buffers/event for safety");
      // Intentionally keep shared ownership of driver-visible memory alive.
      static_cast<void>(
          new std::list<std::shared_ptr<Buffer>>(std::move(buffers)));
    } else if (completion) {
      CloseHandle(completion);
    }
  }

  void Error(const std::string& message) {
    errors.fetch_add(1);
    Log(message);
  }

  void WaveError(const char* operation, MMRESULT result) {
    errors.fetch_add(1);
    LogWaveError(operation, result);
  }

  uint64_t Invalidate() {
    std::lock_guard<std::mutex> lock(commands_mutex);
    accepting = false;
    radio_format.store(false);
    queued_frames.store(0);
    queued_radio_frames = 0;
    return ++generation;
  }

  bool IsCurrent(uint64_t expected) {
    std::lock_guard<std::mutex> lock(commands_mutex);
    return generation == expected;
  }

  bool RemoveFrames(const Buffer& buffer) {
    std::lock_guard<std::mutex> lock(commands_mutex);
    if (buffer.generation != generation) return false;
    queued_frames.fetch_sub(buffer.frames);
    if (buffer.radio) queued_radio_frames -= buffer.frames;
    return true;
  }

  bool Configure(int rate, int channels, const std::string& device_id,
                 bool release) {
    const uint64_t expected = Invalidate();
    return Invoke([this, rate, channels, device_id, release, expected] {
      if (!IsCurrent(expected)) return false;
      const bool success =
          release ? CloseDevice() : Setup(rate, channels, device_id);
      std::lock_guard<std::mutex> lock(commands_mutex);
      if (generation != expected) return false;
      accepting = success && !release;
      admitted_rate = rate;
      admitted_frame_bytes = success && !release ? channels * 2 : 0;
      radio_format.store(accepting && rate == 32000 && channels == 1);
      return success;
    });
  }

  bool Invoke(std::function<bool()> operation) {
    if (!worker.joinable()) {
      Error("Output worker is unavailable");
      return false;
    }
    // Allows a notification callback to query/reconfigure the output without
    // deadlocking. No caller holds the command mutex while waiting.
    if (std::this_thread::get_id() == worker.get_id()) return operation();
    auto task =
        std::make_shared<std::packaged_task<bool()>>(std::move(operation));
    auto result = task->get_future();
    {
      std::lock_guard<std::mutex> lock(commands_mutex);
      commands.push_back({[task] { (*task)(); }});
    }
    SetEvent(wake);
    try {
      return result.get();
    } catch (const std::exception& error) {
      Error(std::string("Output operation failed: ") + error.what());
      return false;
    }
  }

  void Run() {
    const HANDLE events[] = {completion, wake};
    while (!stopping) {
      CollectDone();
      std::function<void()> command;
      {
        std::lock_guard<std::mutex> lock(commands_mutex);
        if (!commands.empty()) {
          command = std::move(commands.front().run);
          commands.pop_front();
        }
      }
      if (command) {
        command();
      } else {
        const DWORD wait = WaitForMultipleObjects(2, events, FALSE, INFINITE);
        if (wait == WAIT_FAILED) {
          Error("Output event wait failed: " + std::to_string(GetLastError()));
          // Keep the worker alive so queued synchronous calls cannot hang.
          Sleep(1);
        }
      }
    }
  }

  bool ResetBuffers() {
    const MMRESULT reset = waveOutReset(device);
    if (reset != MMSYSERR_NOERROR) WaveError("waveOutReset", reset);
    for (auto it = buffers.begin(); it != buffers.end();) {
      Buffer& buffer = **it;
      const MMRESULT result = waveOutUnprepareHeader(
          device, &buffer.header, sizeof(WAVEHDR));
      if (result == MMSYSERR_NOERROR) {
        RemoveFrames(buffer);
        it = buffers.erase(it);
      } else {
        WaveError("waveOutUnprepareHeader (reset)", result);
        ++it;
      }
    }
    return reset == MMSYSERR_NOERROR && buffers.empty();
  }

  bool CloseDevice() {
    open = false;
    if (!device) return true;
    ResetBuffers();
    if (!buffers.empty()) return false;
    const MMRESULT result = waveOutClose(device);
    if (result != MMSYSERR_NOERROR) {
      WaveError("waveOutClose", result);
      return false;
    }
    device = nullptr;
    ResetEvent(completion);
    return true;
  }

  bool Setup(int rate, int channels, const std::string& device_id) {
    if (!CloseDevice()) return false;
    if (rate <= 0 || channels <= 0 ||
        channels > (std::numeric_limits<WORD>::max)() / 2 ||
        static_cast<uint64_t>(rate) * static_cast<uint64_t>(channels) * 2 >
            (std::numeric_limits<DWORD>::max)()) {
      Error("Setup rejected invalid PCM sample rate/channel count");
      return false;
    }
    WAVEFORMATEX format = {};
    format.wFormatTag = WAVE_FORMAT_PCM;
    format.nChannels = static_cast<WORD>(channels);
    format.nSamplesPerSec = static_cast<DWORD>(rate);
    format.wBitsPerSample = 16;
    format.nBlockAlign = static_cast<WORD>(channels * 2);
    format.nAvgBytesPerSec = format.nSamplesPerSec * format.nBlockAlign;

    UINT device_index = WAVE_MAPPER;
    if (!device_id.empty()) {
      try {
        const unsigned long index = std::stoul(device_id);
        if (index < waveOutGetNumDevs()) {
          device_index = static_cast<UINT>(index);
        } else {
          Log("Selected output device is unavailable; using default");
        }
      } catch (...) {
        Log("Invalid output device ID; using default");
      }
    }
    MMRESULT result = waveOutOpen(
        &device, device_index, &format,
        reinterpret_cast<DWORD_PTR>(completion), 0, CALLBACK_EVENT);
    if (result != MMSYSERR_NOERROR && device_index != WAVE_MAPPER) {
      WaveError("waveOutOpen (selected device; trying default)", result);
      result = waveOutOpen(&device, WAVE_MAPPER, &format,
                           reinterpret_cast<DWORD_PTR>(completion), 0,
                           CALLBACK_EVENT);
    }
    if (result != MMSYSERR_NOERROR) {
      device = nullptr;
      WaveError("waveOutOpen", result);
      return false;
    }
    open = true;
    return true;
  }

  bool Feed(const uint8_t* data, size_t length, bool radio_only = false) {
    std::lock_guard<std::mutex> lock(commands_mutex);
    if (!accepting ||
        (radio_only &&
         (admitted_rate != 32000 || admitted_frame_bytes != 2)) ||
        !data || length == 0 ||
        length > (std::numeric_limits<DWORD>::max)() ||
        length % static_cast<size_t>(admitted_frame_bytes) != 0) {
      Error(radio_only
                ? "Radio feed rejected: requires ready 32000 Hz mono and valid PCM"
                : "Feed rejected: output closed, empty data, or invalid PCM alignment/size");
      return false;
    }
    int64_t frames =
        static_cast<int64_t>(length / static_cast<size_t>(admitted_frame_bytes));
    const int64_t limit = static_cast<int64_t>(admitted_rate) * 800 / 1000;
    const int64_t queued = queued_frames.load();
    const bool catchup = radio_only && queued_radio_frames == queued &&
                         queued + frames > admitted_rate * 200 / 1000;
    if (frames > limit || (!catchup && frames > limit - queued)) {
      const uint64_t count = overflows.fetch_add(1) + 1;
      if (count == 1 || count % 100 == 0) {
        Log("Feed overflow: 800 ms queue limit; rejected feeds=" +
            std::to_string(count));
      }
      return false;
    }
    try {
      const int64_t original_frames = frames;
      if (catchup && frames > admitted_rate * 60 / 1000) {
        frames = admitted_rate * 60 / 1000;
        const size_t retained = static_cast<size_t>(frames) *
                                static_cast<size_t>(admitted_frame_bytes);
        data += length - retained;
        length = retained;
      }
      auto buffer = std::make_shared<Buffer>();
      buffer->bytes.assign(data, data + length);
      buffer->frames = frames;
      buffer->generation = generation + (catchup ? 1 : 0);
      buffer->radio = radio_only;
      buffer->header.lpData = reinterpret_cast<char*>(buffer->bytes.data());
      buffer->header.dwBufferLength = static_cast<DWORD>(length);
      commands.push_back({[this, buffer, catchup] {
        try {
          if (catchup && IsCurrent(buffer->generation)) {
            if (!ResetBuffers()) {
              open = false;
              std::lock_guard<std::mutex> lock(commands_mutex);
              if (generation == buffer->generation) {
                accepting = false;
                radio_format.store(false);
              }
              Error("Radio catch-up failed; output disabled until setup");
            } else {
              Log("Radio playback caught up; stale speaker buffers reset");
            }
          }
          Submit(buffer);
        } catch (const std::exception& error) {
          RemoveFrames(*buffer);
          Error(std::string("PCM submission failed: ") + error.what());
        }
      }, true});
      if (catchup) {
        ++generation;
        ++catchups;
        discarded_frames +=
            static_cast<uint64_t>(queued + original_frames - frames);
        queued_frames.store(0);
        queued_radio_frames = 0;
        // Keep control operations, but release stale PCM even if the worker
        // is stalled through several catch-up cycles.
        for (auto it = commands.begin(); it != commands.end() - 1;) {
          if (it->playback) {
            it = commands.erase(it);
          } else {
            ++it;
          }
        }
      }
      queued_frames.fetch_add(frames);
      if (radio_only) queued_radio_frames += frames;
      const int64_t buffered_ms = queued_frames.load() * 1000 / admitted_rate;
      if (buffered_ms > peak_buffered_ms) peak_buffered_ms = buffered_ms;
      SetEvent(wake);
      return true;
    } catch (const std::exception& error) {
      Error(std::string("Cannot enqueue PCM: ") + error.what());
      return false;
    }
  }

  void Submit(const std::shared_ptr<Buffer>& buffer) {
    if (!IsCurrent(buffer->generation)) return;
    if (!open) {
      RemoveFrames(*buffer);
      Error("Queued feed discarded because output failed");
      return;
    }
    buffers.push_back(buffer);
    Buffer& pending = *buffers.back();
    MMRESULT result =
        waveOutPrepareHeader(device, &pending.header, sizeof(WAVEHDR));
    if (result != MMSYSERR_NOERROR) {
      WaveError("waveOutPrepareHeader", result);
      RemoveFrames(pending);
      buffers.pop_back();
      return;
    }
    result = waveOutWrite(device, &pending.header, sizeof(WAVEHDR));
    if (result != MMSYSERR_NOERROR) {
      WaveError("waveOutWrite", result);
      RemoveFrames(pending);
      const MMRESULT unprepare =
          waveOutUnprepareHeader(device, &pending.header, sizeof(WAVEHDR));
      if (unprepare == MMSYSERR_NOERROR) {
        buffers.pop_back();
      } else {
        WaveError("waveOutUnprepareHeader (failed feed)", unprepare);
        // Retain a possibly driver-owned header for the next reset/teardown.
        pending.frames = 0;
        open = false;
        std::lock_guard<std::mutex> lock(commands_mutex);
        if (pending.generation == generation) {
          accepting = false;
          radio_format.store(false);
        }
      }
      return;
    }
  }

  void CollectDone() {
    bool completed = false;
    for (auto it = buffers.begin(); it != buffers.end();) {
      Buffer& buffer = **it;
      if ((buffer.header.dwFlags & WHDR_DONE) == 0) {
        ++it;
        continue;
      }
      const MMRESULT result =
          waveOutUnprepareHeader(device, &buffer.header, sizeof(WAVEHDR));
      if (result != MMSYSERR_NOERROR) {
        WaveError("waveOutUnprepareHeader (completion)", result);
        ++it;
        continue;
      }
      completed = RemoveFrames(buffer) || completed;
      it = buffers.erase(it);
    }
    if (!completed || !open) return;
    const int64_t remaining = queued_frames.load();
    if (remaining == 0) underruns.fetch_add(1);
    // Copy before invoking: a callback may replace/clear itself.
    const auto notify = callback;
    if (notify) {
      try {
        notify(remaining);
      } catch (...) {
        Error("Feed notification callback threw an exception");
      }
    }
  }
};

NativePcmOutput::NativePcmOutput() : impl_(std::make_unique<Impl>()) {}
NativePcmOutput::~NativePcmOutput() = default;

bool NativePcmOutput::Setup(int rate, int channels,
                            const std::string& device_id) {
  return impl_->Configure(rate, channels, device_id, false);
}

bool NativePcmOutput::Feed(const uint8_t* data, size_t length) {
  return impl_->Feed(data, length);
}

bool NativePcmOutput::FeedRadio(const int16_t* pcm, size_t count) {
  if (count > (std::numeric_limits<size_t>::max)() / sizeof(int16_t)) {
    impl_->Error("Radio feed rejected: sample count overflow");
    return false;
  }
  return impl_->Feed(reinterpret_cast<const uint8_t*>(pcm),
                     count * sizeof(int16_t), true);
}

void NativePcmOutput::Release() {
  impl_->Configure(0, 0, "", true);
}

int64_t NativePcmOutput::buffered_frames() const {
  return impl_->queued_frames.load();
}

bool NativePcmOutput::IsRadioFormat() const {
  return impl_->radio_format.load();
}

void NativePcmOutput::SetFeedCallback(std::function<void(int64_t)> callback) {
  impl_->Invoke([this, callback = std::move(callback)]() mutable {
    impl_->callback = std::move(callback);
    return true;
  });
}

NativePcmOutput::Stats NativePcmOutput::stats() const {
  std::lock_guard<std::mutex> lock(impl_->commands_mutex);
  const int64_t queued = impl_->queued_frames.load();
  return {impl_->queued_frames.load(), impl_->underruns.load(),
          impl_->overflows.load(), impl_->errors.load(),
          impl_->admitted_rate > 0 ? queued * 1000 / impl_->admitted_rate : 0,
          impl_->peak_buffered_ms, impl_->catchups, impl_->discarded_frames};
}

uint64_t NativePcmOutput::overflow_count() const {
  return impl_->overflows.load();
}

uint64_t NativePcmOutput::underrun_count() const {
  return impl_->underruns.load();
}

uint64_t NativePcmOutput::error_count() const {
  return impl_->errors.load();
}
