#include "flutter_window.h"

#include <optional>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include <desktop_multi_window/desktop_multi_window_plugin.h>

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

  // Detached tabs open in secondary windows created by desktop_multi_window.
  // Those windows run in their own Flutter engine, which does NOT get plugins
  // registered automatically - so window_manager, record, file_picker, etc.
  // would throw MissingPluginException and crash the detached window. Register
  // all plugins (and the app-specific native plugins) for every sub-window as
  // it is created.
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    auto* view_controller =
        reinterpret_cast<flutter::FlutterViewController*>(controller);
    auto* engine = view_controller->engine();
    RegisterPlugins(engine);
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
