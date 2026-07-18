#include "flutter_window.h"

#include <optional>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include <desktop_multi_window/desktop_multi_window_plugin.h>

// Individual plugin headers so detached (secondary) windows can register every
// plugin EXCEPT window_manager. See the sub-window created callback below for
// why window_manager must be skipped. This list mirrors
// flutter/generated_plugin_registrant.cc (minus window_manager) and must be
// kept in sync when the plugin set changes.
#include <audioplayers_windows/audioplayers_windows_plugin.h>
#include <desktop_drop/desktop_drop_plugin.h>
#include <desktop_updater/desktop_updater_plugin_c_api.h>
#include <flutter_tts/flutter_tts_plugin.h>
#include <pasteboard/pasteboard_plugin.h>
#include <permission_handler_windows/permission_handler_windows_plugin.h>
#include <record_windows/record_windows_plugin_c_api.h>
#include <screen_retriever_windows/screen_retriever_windows_plugin_c_api.h>
#include <url_launcher_windows/url_launcher_windows.h>

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  bluetooth_plugin_ = std::make_unique<BluetoothClassicPlugin>(
      flutter_controller_->engine()->messenger());
  pcm_player_plugin_ = std::make_unique<PcmPlayerPlugin>(
      flutter_controller_->engine()->messenger());
  tts_plugin_ = std::make_unique<TtsPlugin>(
      flutter_controller_->engine()->messenger());

  // Detached tabs open in secondary windows created by desktop_multi_window.
  // Those windows run in their own Flutter engine, which does NOT get plugins
  // registered automatically - so record, file_picker, etc. would throw
  // MissingPluginException and crash the detached window. Register the plugins
  // (and the app-specific native plugins) for every sub-window as it is
  // created.
  //
  // IMPORTANT: window_manager is deliberately NOT registered for sub-windows.
  // Its Windows plugin keeps its Flutter MethodChannel in a single
  // process-global variable that RegisterWithRegistrar overwrites on every
  // call. Registering it here would rebind that global channel to the
  // sub-window's engine, so the MAIN window's WM_CLOSE handler would emit its
  // "close" event to the wrong (or, once the detached window is closed,
  // destroyed) engine. Because the main window uses setPreventClose(true), it
  // would then silently refuse to close after a tab was detached. Detached
  // windows only use window_manager for a cosmetic title / minimum size (which
  // is optional and guarded in Dart), so we leave the global channel owned by
  // the main window.
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    auto* view_controller =
        reinterpret_cast<flutter::FlutterViewController*>(controller);
    auto* engine = view_controller->engine();

    // Mirror generated_plugin_registrant.cc, minus window_manager (see above).
    AudioplayersWindowsPluginRegisterWithRegistrar(
        engine->GetRegistrarForPlugin("AudioplayersWindowsPlugin"));
    DesktopDropPluginRegisterWithRegistrar(
        engine->GetRegistrarForPlugin("DesktopDropPlugin"));
    DesktopMultiWindowPluginRegisterWithRegistrar(
        engine->GetRegistrarForPlugin("DesktopMultiWindowPlugin"));
    DesktopUpdaterPluginCApiRegisterWithRegistrar(
        engine->GetRegistrarForPlugin("DesktopUpdaterPluginCApi"));
    FlutterTtsPluginRegisterWithRegistrar(
        engine->GetRegistrarForPlugin("FlutterTtsPlugin"));
    PasteboardPluginRegisterWithRegistrar(
        engine->GetRegistrarForPlugin("PasteboardPlugin"));
    PermissionHandlerWindowsPluginRegisterWithRegistrar(
        engine->GetRegistrarForPlugin("PermissionHandlerWindowsPlugin"));
    RecordWindowsPluginCApiRegisterWithRegistrar(
        engine->GetRegistrarForPlugin("RecordWindowsPluginCApi"));
    ScreenRetrieverWindowsPluginCApiRegisterWithRegistrar(
        engine->GetRegistrarForPlugin("ScreenRetrieverWindowsPluginCApi"));
    UrlLauncherWindowsRegisterWithRegistrar(
        engine->GetRegistrarForPlugin("UrlLauncherWindows"));

    // Keep the app-specific plugin instances alive for the sub-window's
    // lifetime.
    static std::vector<std::unique_ptr<BluetoothClassicPlugin>> bt_plugins;
    static std::vector<std::unique_ptr<PcmPlayerPlugin>> pcm_plugins;
    bt_plugins.push_back(
        std::make_unique<BluetoothClassicPlugin>(engine->messenger()));
    pcm_plugins.push_back(
        std::make_unique<PcmPlayerPlugin>(engine->messenger()));
  });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
