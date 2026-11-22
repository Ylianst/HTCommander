// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#pragma once

#include <atomic>
#include <memory>
#include <mutex>
#include <thread>
#include <utility>
#include <vector>

// Owns background callbacks until they finish, even after a connection leaves
// its map. Close admission before cancelling I/O, then Join before destroying
// any state or messenger captured by the callbacks.
class NativeThreadGroup {
 public:
  ~NativeThreadGroup() {
    Close();
    Join();
  }

  template <typename Callback>
  bool Start(Callback callback) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (closed_) return false;
    for (auto it = workers_.begin(); it != workers_.end();) {
      if (it->done->load()) {
        it->thread.join();
        it = workers_.erase(it);
      } else {
        ++it;
      }
    }
    auto done = std::make_shared<std::atomic<bool>>(false);
    // Allocate the slot before starting: allocation failure must not destroy
    // a joinable thread or strand an untracked callback.
    workers_.emplace_back();
    try {
      workers_.back().done = done;
      workers_.back().thread = std::thread(
          [callback = std::move(callback), done]() mutable {
            callback();
            done->store(true);
          });
    } catch (...) {
      workers_.pop_back();
      throw;
    }
    return true;
  }

  void Close() {
    std::lock_guard<std::mutex> lock(mutex_);
    closed_ = true;
  }

  void Join() {
    std::vector<Worker> workers;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      workers.swap(workers_);
    }
    for (auto& worker : workers) worker.thread.join();
  }

 private:
  struct Worker {
    std::thread thread;
    std::shared_ptr<std::atomic<bool>> done;
  };
  std::mutex mutex_;
  std::vector<Worker> workers_;
  bool closed_ = false;
};
