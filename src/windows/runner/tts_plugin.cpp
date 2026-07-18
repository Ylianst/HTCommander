// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
//
// Windows text-to-speech plugin backed by SAPI 5 (ISpVoice).
//
// flutter_tts has no working Windows synthesis path, so this native plugin
// provides the same in-memory synthesis the Apple runners expose over the
// shared "com.htcommander/tts" MethodChannel (see tts_plugin.h for the
// contract and lib/services/tts_service_io.dart for the Dart consumer).
//
// Threading: `getVoices`, `preview` and `stopPreview` are cheap and run on the
// platform thread (COM is initialized there in the constructor). `synthesize`
// can take noticeable time, so it runs on a detached worker thread (with its
// own COM apartment); the result is marshalled back to the platform thread via
// a message-only window before the Flutter reply is sent, exactly like
// pcm_player_plugin.cpp marshals its waveOut callbacks.

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <ole2.h>
#include <sapi.h>

#include <cmath>
#include <cstdint>
#include <memory>
#include <string>
#include <thread>
#include <vector>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <flutter/standard_method_codec.h>

#include "tts_plugin.h"

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr char kMethodChannelName[] = "com.htcommander/tts";
constexpr UINT kSynthDoneMessage = WM_USER + 0x60;
constexpr wchar_t kWindowClassName[] = L"HTCommanderTtsWindow";

// SAPI always renders into this fixed 16-bit mono format; the Dart side
// resamples to the 32 kHz radio audio rate.
constexpr int kSynthSampleRate = 22050;

// ---------------------------------------------------------------------------
// Small argument / string helpers
// ---------------------------------------------------------------------------

std::string GetStringArg(const EncodableMap* args, const char* key) {
  if (!args) return "";
  auto it = args->find(EncodableValue(std::string(key)));
  if (it == args->end()) return "";
  if (const auto* v = std::get_if<std::string>(&it->second)) return *v;
  return "";
}

double GetDoubleArg(const EncodableMap* args, const char* key, double fallback) {
  if (!args) return fallback;
  auto it = args->find(EncodableValue(std::string(key)));
  if (it == args->end()) return fallback;
  if (const auto* v = std::get_if<double>(&it->second)) return *v;
  if (const auto* v = std::get_if<int32_t>(&it->second)) return *v;
  if (const auto* v = std::get_if<int64_t>(&it->second)) {
    return static_cast<double>(*v);
  }
  return fallback;
}

std::wstring Utf8ToUtf16(const std::string& s) {
  if (s.empty()) return std::wstring();
  int len = MultiByteToWideChar(CP_UTF8, 0, s.data(),
                                static_cast<int>(s.size()), nullptr, 0);
  std::wstring out(len, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                      out.data(), len);
  return out;
}

std::string Utf16ToUtf8(const wchar_t* s) {
  if (!s || !*s) return "";
  int len = WideCharToMultiByte(CP_UTF8, 0, s, -1, nullptr, 0, nullptr, nullptr);
  if (len <= 0) return "";
  std::string out(len - 1, '\0');  // exclude null terminator
  WideCharToMultiByte(CP_UTF8, 0, s, -1, out.data(), len, nullptr, nullptr);
  return out;
}

std::string ToLower(std::string s) {
  for (auto& c : s) c = static_cast<char>(::tolower(static_cast<unsigned char>(c)));
  return s;
}

// Maps a normalized rate (0.0-1.0, 0.5 = normal) to the SAPI -10..10 range.
long RateToSapi(double rate) {
  long r = std::lround((rate - 0.5) * 20.0);
  if (r < -10) r = -10;
  if (r > 10) r = 10;
  return r;
}

// Escapes text for inclusion in a SAPI XML fragment.
std::wstring XmlEscape(const std::wstring& in) {
  std::wstring out;
  out.reserve(in.size());
  for (wchar_t c : in) {
    switch (c) {
      case L'&': out += L"&amp;"; break;
      case L'<': out += L"&lt;"; break;
      case L'>': out += L"&gt;"; break;
      case L'"': out += L"&quot;"; break;
      case L'\'': out += L"&apos;"; break;
      default: out += c; break;
    }
  }
  return out;
}

// Wraps text in a SAPI <pitch> element mapping pitch (0.5-2.0, 1.0 = normal)
// to the -10..10 absmiddle scale.
std::wstring BuildPitchXml(const std::wstring& text, double pitch) {
  long p = (pitch >= 1.0) ? std::lround((pitch - 1.0) * 10.0)
                          : std::lround((pitch - 1.0) * 20.0);
  if (p < -10) p = -10;
  if (p > 10) p = 10;
  wchar_t num[16];
  swprintf(num, 16, L"%ld", p);
  return L"<pitch absmiddle=\"" + std::wstring(num) + L"\">" + XmlEscape(text) +
         L"</pitch>";
}

// Converts a SAPI "Language" attribute (hex LCID list, e.g. "409" or "409;80a")
// into a BCP-47 locale (e.g. "en-US"). Returns "" if it cannot be resolved.
std::string LcidHexToBcp47(const wchar_t* langHex) {
  if (!langHex || !*langHex) return "";
  std::wstring first(langHex);
  size_t sep = first.find(L';');
  if (sep != std::wstring::npos) first = first.substr(0, sep);
  wchar_t* end = nullptr;
  unsigned long lcid = wcstoul(first.c_str(), &end, 16);
  if (lcid == 0) return "";
  wchar_t name[LOCALE_NAME_MAX_LENGTH] = {};
  int n = LCIDToLocaleName(static_cast<LCID>(lcid), name,
                           LOCALE_NAME_MAX_LENGTH, 0);
  if (n <= 0) return "";
  return Utf16ToUtf8(name);
}

// Reads a string value from a token's "Attributes" subkey. Returns "" if the
// attribute is missing.
std::string ReadTokenAttribute(ISpObjectToken* token, const wchar_t* attr) {
  if (!token) return "";
  ISpDataKey* key = nullptr;
  if (FAILED(token->OpenKey(L"Attributes", &key)) || !key) return "";
  std::string result;
  LPWSTR value = nullptr;
  if (SUCCEEDED(key->GetStringValue(attr, &value)) && value) {
    result = Utf16ToUtf8(value);
    CoTaskMemFree(value);
  }
  key->Release();
  return result;
}

// Returns the BCP-47 locale advertised by a voice token, or "".
std::string TokenLocale(ISpObjectToken* token) {
  if (!token) return "";
  ISpDataKey* key = nullptr;
  if (FAILED(token->OpenKey(L"Attributes", &key)) || !key) return "";
  std::string locale;
  LPWSTR value = nullptr;
  if (SUCCEEDED(key->GetStringValue(L"Language", &value)) && value) {
    locale = LcidHexToBcp47(value);
    CoTaskMemFree(value);
  }
  key->Release();
  return locale;
}

// Enumerates the installed SAPI voices. Requires COM to be initialized on the
// calling thread.
EncodableValue EnumerateVoices() {
  EncodableList list;
  ISpObjectTokenCategory* category = nullptr;
  if (FAILED(CoCreateInstance(CLSID_SpObjectTokenCategory, nullptr, CLSCTX_ALL,
                              IID_ISpObjectTokenCategory,
                              reinterpret_cast<void**>(&category))) ||
      !category) {
    return EncodableValue(list);
  }
  if (SUCCEEDED(category->SetId(SPCAT_VOICES, FALSE))) {
    IEnumSpObjectTokens* tokens = nullptr;
    if (SUCCEEDED(category->EnumTokens(nullptr, nullptr, &tokens)) && tokens) {
      ISpObjectToken* token = nullptr;
      while (tokens->Next(1, &token, nullptr) == S_OK && token) {
        EncodableMap voice;
        LPWSTR id = nullptr;
        if (SUCCEEDED(token->GetId(&id)) && id) {
          voice[EncodableValue("identifier")] = EncodableValue(Utf16ToUtf8(id));
          CoTaskMemFree(id);
        }
        LPWSTR name = nullptr;
        if (SUCCEEDED(token->GetStringValue(nullptr, &name)) && name) {
          voice[EncodableValue("name")] = EncodableValue(Utf16ToUtf8(name));
          CoTaskMemFree(name);
        }
        const std::string locale = TokenLocale(token);
        if (!locale.empty()) {
          voice[EncodableValue("locale")] = EncodableValue(locale);
        }
        std::string gender = ToLower(ReadTokenAttribute(token, L"Gender"));
        if (!gender.empty()) {
          voice[EncodableValue("gender")] = EncodableValue(gender);
        }
        list.push_back(EncodableValue(voice));
        token->Release();
        token = nullptr;
      }
      tokens->Release();
    }
  }
  category->Release();
  return EncodableValue(list);
}

// Finds a voice token matching |voiceId| (SAPI token id) first, then falling
// back to the first token whose locale matches |locale|. Returns an AddRef'd
// token (caller releases) or nullptr. Requires COM on the calling thread.
ISpObjectToken* FindVoiceToken(const std::string& voiceId,
                               const std::string& locale) {
  ISpObjectTokenCategory* category = nullptr;
  if (FAILED(CoCreateInstance(CLSID_SpObjectTokenCategory, nullptr, CLSCTX_ALL,
                              IID_ISpObjectTokenCategory,
                              reinterpret_cast<void**>(&category))) ||
      !category) {
    return nullptr;
  }
  ISpObjectToken* found = nullptr;
  ISpObjectToken* localeMatch = nullptr;
  if (SUCCEEDED(category->SetId(SPCAT_VOICES, FALSE))) {
    IEnumSpObjectTokens* tokens = nullptr;
    if (SUCCEEDED(category->EnumTokens(nullptr, nullptr, &tokens)) && tokens) {
      ISpObjectToken* token = nullptr;
      while (tokens->Next(1, &token, nullptr) == S_OK && token) {
        bool matched = false;
        if (!voiceId.empty()) {
          LPWSTR id = nullptr;
          if (SUCCEEDED(token->GetId(&id)) && id) {
            if (Utf16ToUtf8(id) == voiceId) matched = true;
            CoTaskMemFree(id);
          }
        }
        if (matched) {
          found = token;  // keep the ref from Next()
          token = nullptr;
          break;
        }
        if (!localeMatch && !locale.empty() && TokenLocale(token) == locale) {
          localeMatch = token;
          localeMatch->AddRef();
        }
        token->Release();
        token = nullptr;
      }
      tokens->Release();
    }
  }
  category->Release();
  if (found) {
    if (localeMatch) localeMatch->Release();
    return found;
  }
  return localeMatch;
}

// Synthesizes |text| into mono float samples using SAPI. Requires COM on the
// calling thread. Returns true and fills |outSamples| / |outRate| on success.
bool SynthesizeToPcm(const std::wstring& text, const std::string& voiceId,
                     const std::string& locale, double rate, double pitch,
                     std::vector<float>* outSamples, int* outRate) {
  if (text.empty()) return false;

  ISpVoice* voice = nullptr;
  if (FAILED(CoCreateInstance(CLSID_SpVoice, nullptr, CLSCTX_ALL, IID_ISpVoice,
                              reinterpret_cast<void**>(&voice))) ||
      !voice) {
    return false;
  }

  if (ISpObjectToken* token = FindVoiceToken(voiceId, locale)) {
    voice->SetVoice(token);
    token->Release();
  }
  voice->SetRate(RateToSapi(rate));

  IStream* mem = nullptr;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &mem)) || !mem) {
    voice->Release();
    return false;
  }

  ISpStream* stream = nullptr;
  if (FAILED(CoCreateInstance(CLSID_SpStream, nullptr, CLSCTX_ALL,
                              IID_ISpStream,
                              reinterpret_cast<void**>(&stream))) ||
      !stream) {
    mem->Release();
    voice->Release();
    return false;
  }

  WAVEFORMATEX wfex = {};
  wfex.wFormatTag = WAVE_FORMAT_PCM;
  wfex.nChannels = 1;
  wfex.nSamplesPerSec = kSynthSampleRate;
  wfex.wBitsPerSample = 16;
  wfex.nBlockAlign = 2;
  wfex.nAvgBytesPerSec = kSynthSampleRate * 2;
  wfex.cbSize = 0;

  bool ok = false;
  if (SUCCEEDED(stream->SetBaseStream(mem, SPDFID_WaveFormatEx, &wfex))) {
    voice->SetOutput(stream, TRUE);
    const std::wstring xml = BuildPitchXml(text, pitch);
    HRESULT hr = voice->Speak(xml.c_str(), SPF_IS_XML | SPF_PURGEBEFORESPEAK,
                              nullptr);
    voice->SetOutput(nullptr, TRUE);  // detach before reading

    if (SUCCEEDED(hr)) {
      STATSTG stat = {};
      if (SUCCEEDED(mem->Stat(&stat, STATFLAG_NONAME))) {
        const ULONGLONG bytes = stat.cbSize.QuadPart;
        if (bytes >= 2) {
          LARGE_INTEGER zero = {};
          mem->Seek(zero, STREAM_SEEK_SET, nullptr);
          std::vector<int16_t> pcm(static_cast<size_t>(bytes / 2));
          ULONG read = 0;
          if (SUCCEEDED(mem->Read(pcm.data(),
                                  static_cast<ULONG>(pcm.size() * 2), &read))) {
            const size_t n = read / 2;
            outSamples->resize(n);
            for (size_t i = 0; i < n; ++i) {
              (*outSamples)[i] = static_cast<float>(pcm[i]) / 32768.0f;
            }
            *outRate = kSynthSampleRate;
            ok = n > 0;
          }
        }
      }
    }
  }

  stream->Release();
  mem->Release();
  voice->Release();
  return ok;
}

// Heap payload carried from the synthesis worker thread back to the platform
// thread, where the Flutter reply must be sent.
struct PendingSynth {
  std::unique_ptr<flutter::MethodResult<EncodableValue>> result;
  std::vector<float> samples;
  int sample_rate = 0;
  bool ok = false;
};

}  // namespace

// ---------------------------------------------------------------------------
// Pimpl
// ---------------------------------------------------------------------------
struct TtsPlugin::Impl {
  explicit Impl(flutter::BinaryMessenger* messenger);
  ~Impl();

  std::unique_ptr<flutter::MethodChannel<EncodableValue>> method_channel;

  // COM initialized on the platform thread for getVoices / preview.
  bool com_owned = false;
  // Message-only window used to marshal synthesis results back here.
  HWND hwnd = nullptr;
  // Persistent voice used for local "preview" playback in Settings.
  ISpVoice* preview_voice = nullptr;

  void HandleMethodCall(
      const flutter::MethodCall<EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);

  void Preview(const EncodableMap* args);
  void StopPreview();
  void EnsurePreviewVoice();

  void EnsureWindow();
  void DestroyWindowSafe();

  static LRESULT CALLBACK WndProc(HWND, UINT, WPARAM, LPARAM);
};

TtsPlugin::Impl::Impl(flutter::BinaryMessenger* messenger) {
  // Initialize COM on the platform thread. S_FALSE means it was already
  // initialized here (still balanced with CoUninitialize); RPC_E_CHANGED_MODE
  // means COM is available in another mode (do not balance).
  HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  com_owned = (hr == S_OK || hr == S_FALSE);

  EnsureWindow();

  method_channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, kMethodChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  method_channel->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}

TtsPlugin::Impl::~Impl() {
  if (preview_voice) {
    preview_voice->Speak(nullptr, SPF_PURGEBEFORESPEAK, nullptr);
    preview_voice->Release();
    preview_voice = nullptr;
  }
  DestroyWindowSafe();
  if (com_owned) {
    CoUninitialize();
    com_owned = false;
  }
}

void TtsPlugin::Impl::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  const auto* args = std::get_if<EncodableMap>(call.arguments());

  if (method == "getVoices") {
    result->Success(EnumerateVoices());
    return;
  }
  if (method == "synthesize") {
    const std::wstring text = Utf8ToUtf16(GetStringArg(args, "text"));
    if (text.empty()) {
      result->Success(EncodableValue());  // null
      return;
    }
    const std::string voiceId = GetStringArg(args, "voiceIdentifier");
    const std::string locale = GetStringArg(args, "locale");
    const double rate = GetDoubleArg(args, "rate", 0.5);
    const double pitch = GetDoubleArg(args, "pitch", 1.0);

    auto* pending = new PendingSynth();
    pending->result = std::move(result);
    HWND target = hwnd;

    std::thread([target, pending, text, voiceId, locale, rate, pitch]() {
      HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
      const bool owned = SUCCEEDED(hr);
      pending->ok = SynthesizeToPcm(text, voiceId, locale, rate, pitch,
                                    &pending->samples, &pending->sample_rate);
      if (owned) CoUninitialize();
      ::PostMessageW(target, kSynthDoneMessage, 0,
                     reinterpret_cast<LPARAM>(pending));
    }).detach();
    return;
  }
  if (method == "preview") {
    Preview(args);
    result->Success();
    return;
  }
  if (method == "stopPreview") {
    StopPreview();
    result->Success();
    return;
  }
  result->NotImplemented();
}

void TtsPlugin::Impl::EnsurePreviewVoice() {
  if (preview_voice) return;
  CoCreateInstance(CLSID_SpVoice, nullptr, CLSCTX_ALL, IID_ISpVoice,
                   reinterpret_cast<void**>(&preview_voice));
}

void TtsPlugin::Impl::Preview(const EncodableMap* args) {
  const std::wstring text = Utf8ToUtf16(GetStringArg(args, "text"));
  if (text.empty()) return;
  EnsurePreviewVoice();
  if (!preview_voice) return;

  const std::string voiceId = GetStringArg(args, "voiceIdentifier");
  const std::string locale = GetStringArg(args, "locale");
  if (ISpObjectToken* token = FindVoiceToken(voiceId, locale)) {
    preview_voice->SetVoice(token);
    token->Release();
  }
  preview_voice->SetRate(RateToSapi(GetDoubleArg(args, "rate", 0.5)));

  // Stop anything currently playing, then speak asynchronously to the default
  // output device so the call returns immediately.
  preview_voice->Speak(nullptr, SPF_PURGEBEFORESPEAK, nullptr);
  const std::wstring xml = BuildPitchXml(text, GetDoubleArg(args, "pitch", 1.0));
  preview_voice->Speak(xml.c_str(), SPF_ASYNC | SPF_IS_XML, nullptr);
}

void TtsPlugin::Impl::StopPreview() {
  if (preview_voice) {
    preview_voice->Speak(nullptr, SPF_PURGEBEFORESPEAK, nullptr);
  }
}

void TtsPlugin::Impl::EnsureWindow() {
  if (hwnd) return;
  HINSTANCE instance = ::GetModuleHandleW(nullptr);

  WNDCLASSEXW wc = {};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = &TtsPlugin::Impl::WndProc;
  wc.hInstance = instance;
  wc.lpszClassName = kWindowClassName;
  ::RegisterClassExW(&wc);  // ignore "already registered"

  hwnd = ::CreateWindowExW(0, kWindowClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
                           nullptr, instance, this);
}

void TtsPlugin::Impl::DestroyWindowSafe() {
  if (hwnd) {
    ::DestroyWindow(hwnd);
    hwnd = nullptr;
  }
}

LRESULT CALLBACK TtsPlugin::Impl::WndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                          LPARAM lparam) {
  if (msg == kSynthDoneMessage) {
    auto* pending = reinterpret_cast<PendingSynth*>(lparam);
    if (pending) {
      if (pending->ok && !pending->samples.empty() && pending->sample_rate > 0) {
        EncodableMap payload;
        payload[EncodableValue("samples")] = EncodableValue(pending->samples);
        payload[EncodableValue("sampleRate")] =
            EncodableValue(pending->sample_rate);
        pending->result->Success(EncodableValue(payload));
      } else {
        pending->result->Success(EncodableValue());  // null
      }
      delete pending;
    }
    return 0;
  }
  return ::DefWindowProcW(hwnd, msg, wparam, lparam);
}

// ---------------------------------------------------------------------------
// Public wrapper
// ---------------------------------------------------------------------------
TtsPlugin::TtsPlugin(flutter::BinaryMessenger* messenger)
    : impl_(std::make_unique<Impl>(messenger)) {}

TtsPlugin::~TtsPlugin() = default;
