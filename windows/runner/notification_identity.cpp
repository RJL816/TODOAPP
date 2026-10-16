#include "notification_identity.h"
#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <propkey.h>
#include <propvarutil.h>
#include <wrl/client.h>

bool RefreshNotificationIdentity(const std::string& icon_path) {
  if (icon_path.empty()) return false;
  const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      icon_path.c_str(), -1, nullptr, 0);
  if (count <= 0) return false;
  std::wstring icon(count, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, icon_path.c_str(), -1,
      icon.data(), count);
  icon.resize(count - 1);
  if (GetFileAttributesW(icon.c_str()) == INVALID_FILE_ATTRIBUTES) return false;
  constexpr wchar_t identity[] = L"拾序 · Dayloom";
  wchar_t exe[MAX_PATH];
  const DWORD length = GetModuleFileNameW(nullptr, exe, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) return false;
  PWSTR programs = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_Programs, 0, nullptr, &programs))) return false;
  const std::wstring shortcut = std::wstring(programs) + L"\\" + identity + L".lnk";
  CoTaskMemFree(programs);
  Microsoft::WRL::ComPtr<IShellLinkW> link;
  if (FAILED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
      IID_PPV_ARGS(&link)))) return false;
  link->SetPath(exe);
  link->SetArguments(L"");
  const std::wstring folder = std::wstring(exe).substr(0, std::wstring(exe).find_last_of(L"\\"));
  link->SetWorkingDirectory(folder.c_str());
  link->SetDescription(identity);
  link->SetIconLocation(icon.c_str(), 0);
  Microsoft::WRL::ComPtr<IPropertyStore> properties;
  HRESULT hr = link.As(&properties);
  PROPVARIANT value;
  PropVariantInit(&value);
  if (SUCCEEDED(hr)) hr = InitPropVariantFromString(identity, &value);
  if (SUCCEEDED(hr)) hr = properties->SetValue(PKEY_AppUserModel_ID, value);
  PropVariantClear(&value);
  if (SUCCEEDED(hr)) hr = properties->Commit();
  Microsoft::WRL::ComPtr<IPersistFile> file;
  if (SUCCEEDED(hr)) hr = link.As(&file);
  if (SUCCEEDED(hr)) hr = file->Save(shortcut.c_str(), TRUE);
  if (FAILED(hr)) return false;
  // Refresh only this app's notification identity; no global icon-cache deletion.
  HKEY key = nullptr;
  const std::wstring key_path = std::wstring(L"Software\\Classes\\AppUserModelId\\") + identity;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, key_path.c_str(), 0, nullptr, 0,
      KEY_SET_VALUE, nullptr, &key, nullptr) == ERROR_SUCCESS) {
    RegSetValueExW(key, L"DisplayName", 0, REG_SZ,
        reinterpret_cast<const BYTE*>(identity), sizeof(identity));
    RegSetValueExW(key, L"IconUri", 0, REG_SZ,
        reinterpret_cast<const BYTE*>(icon.c_str()), static_cast<DWORD>((icon.size() + 1) * sizeof(wchar_t)));
    RegCloseKey(key);
  }
  SetCurrentProcessExplicitAppUserModelID(identity);
  SHChangeNotify(SHCNE_UPDATEITEM, SHCNF_PATHW, shortcut.c_str(), nullptr);
  return true;
}
