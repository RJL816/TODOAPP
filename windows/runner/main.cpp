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
const wchar_t* kAutoRunValueName = L"TodoApp";

// Get the full path of current executable
std::wstring GetExecutablePath() {
  wchar_t buffer[MAX_PATH];
  GetModuleFileNameW(nullptr, buffer, MAX_PATH);
  return std::wstring(buffer);
}

// 去掉路径两端的引号（自启动值统一带引号存储，兼容含空格目录）
std::wstring TrimQuotes(const std::wstring& s) {
  if (s.size() >= 2 && s.front() == L'"' && s.back() == L'"') {
    return s.substr(1, s.size() - 2);
  }
  return s;
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
    // 带引号写入，安装目录含空格时也能正确自启
    std::wstring exePath = L"\"" + GetExecutablePath() + L"\"";
    result = RegSetValueExW(hKey, kAutoRunValueName, 0, REG_SZ,
                            (const BYTE*)exePath.c_str(),
                            static_cast<DWORD>((exePath.size() + 1) * sizeof(wchar_t)));
  } else {
    result = RegDeleteValueW(hKey, kAutoRunValueName);
  }

  RegCloseKey(hKey);
  return result == ERROR_SUCCESS;
}

// Check if auto-start points at the current executable.
// 旧版本升级安装位置后，残留的自启动值会指向不存在的旧路径；
// 发现不一致时直接改写为当前路径（自愈），并返回 true。
bool IsAutoStartEnabled() {
  HKEY hKey;
  LONG result = RegOpenKeyExW(HKEY_CURRENT_USER, kAutoRunKeyPath, 0,
                              KEY_QUERY_VALUE | KEY_SET_VALUE, &hKey);
  if (result != ERROR_SUCCESS) {
    return false;
  }

  wchar_t buffer[MAX_PATH * 2];
  DWORD size = sizeof(buffer);
  DWORD type;
  result = RegQueryValueExW(hKey, kAutoRunValueName, nullptr, &type,
                            (BYTE*)buffer, &size);

  if (result != ERROR_SUCCESS || type != REG_SZ) {
    RegCloseKey(hKey);
    return false;
  }

  std::wstring registered = TrimQuotes(buffer);
  std::wstring current = GetExecutablePath();
  // 不区分大小写比较（盘符/目录大小写常有差异）
  if (_wcsicmp(registered.c_str(), current.c_str()) != 0) {
    std::wstring exePath = L"\"" + current + L"\"";
    RegSetValueExW(hKey, kAutoRunValueName, 0, REG_SZ,
                   (const BYTE*)exePath.c_str(),
                   static_cast<DWORD>((exePath.size() + 1) * sizeof(wchar_t)));
  }

  RegCloseKey(hKey);
  return true;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // 单实例锁：重复启动时把已有窗口唤到前台后退出，
  // 防止托盘驻留期间反复开新进程堆积
  HANDLE singleInstance =
      CreateMutexW(nullptr, TRUE, L"TodoApp_SingleInstance_8F3A9C42");
  if (singleInstance && GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr);
    if (existing) {
      ShowWindow(existing, SW_SHOW);
      SetForegroundWindow(existing);
    }
    CloseHandle(singleInstance);
    return EXIT_SUCCESS;
  }

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
  if (!window.Create(L"Dayloom - 拾序", origin, size)) {
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
