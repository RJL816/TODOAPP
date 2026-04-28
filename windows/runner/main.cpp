#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <memory>

// Registry path for Windows auto-start
const wchar_t* kAutoRunKeyPath =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";

// Get the full path of current executable
std::wstring GetExecutablePath() {
  wchar_t buffer[MAX_PATH];
  GetModuleFileNameW(nullptr, buffer, MAX_PATH);
  return std::wstring(buffer);
}

// Set auto-start on Windows boot
bool SetAutoStart(bool enable) {
  HKEY hKey;
  LONG result = RegOpenKeyExW(HKEY_CURRENT_USER, kAutoRunKeyPath, 0,
                              KEY_SET_VALUE, &hKey);
  if (result != ERROR_SUCCESS) {
    return false;
  }

  if (enable) {
    std::wstring exePath = GetExecutablePath();
    result = RegSetValueExW(hKey, L"TodoApp", 0, REG_SZ,
                            (const BYTE*)exePath.c_str(),
                            static_cast<DWORD>((exePath.size() + 1) * sizeof(wchar_t)));
  } else {
    result = RegDeleteValueW(hKey, L"TodoApp");
  }

  RegCloseKey(hKey);
  return result == ERROR_SUCCESS;
}

// Check if auto-start is enabled
bool IsAutoStartEnabled() {
  HKEY hKey;
  LONG result = RegOpenKeyExW(HKEY_CURRENT_USER, kAutoRunKeyPath, 0,
                              KEY_QUERY_VALUE, &hKey);
  if (result != ERROR_SUCCESS) {
    return false;
  }

  wchar_t buffer[MAX_PATH];
  DWORD size = sizeof(buffer);
  DWORD type;
  result = RegQueryValueExW(hKey, L"TodoApp", nullptr, &type,
                            (BYTE*)buffer, &size);

  RegCloseKey(hKey);
  return result == ERROR_SUCCESS;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"todo_app", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // Setup platform channel for auto-start feature
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          window.GetEngine()->engine()->messenger(), "com.todo.app/autostart",
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "setAutoStart") {
          const auto* arguments =
              std::get_if<flutter::EncodableMap>(call.arguments());
          bool enable = false;
          if (arguments) {
            auto it = arguments->find(flutter::EncodableValue("enable"));
            if (it != arguments->end()) {
              enable = std::get<bool>(it->second);
            }
          }
          bool success = SetAutoStart(enable);
          result->Success(flutter::EncodableValue(success));
        } else if (call.method_name() == "isAutoStartEnabled") {
          bool enabled = IsAutoStartEnabled();
          result->Success(flutter::EncodableValue(enabled));
        } else {
          result->NotImplemented();
        }
      });

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
