#include "openvpn_dart_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <shlobj.h>
#include <memory>
#include <sstream>
#include <fstream>
#include <filesystem>
#include <regex>

namespace openvpn_dart
{

  // Static method registration
  void OpenVpnDartPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarWindows *registrar)
  {
    auto method_channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "id.mysteriumvpn.openvpn_flutter/vpncontrol",
            &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<OpenVpnDartPlugin>(registrar);

    method_channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result)
        {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    auto event_channel =
        std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
            registrar->messenger(), "id.mysteriumvpn.openvpn_flutter/vpnstatus",
            &flutter::StandardMethodCodec::GetInstance());

    auto handler = std::make_unique<
        flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
        [plugin_pointer = plugin.get()](
            const flutter::EncodableValue *arguments,
            std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> &&events)
            -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
        {
          return plugin_pointer->OnListenInternal(arguments, std::move(events));
        },
        [plugin_pointer = plugin.get()](const flutter::EncodableValue *arguments)
            -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
        {
          return plugin_pointer->OnCancelInternal(arguments);
        });

    event_channel->SetStreamHandler(std::move(handler));

    registrar->AddPlugin(std::move(plugin));
  }

  OpenVpnDartPlugin::OpenVpnDartPlugin(flutter::PluginRegistrarWindows *registrar)
      : registrar_(registrar),
        process_handle_(nullptr),
        pipe_read_(nullptr),
        pipe_write_(nullptr),
        is_connected_(false),
        is_monitoring_(false),
        current_status_("disconnected")
  {
    ZeroMemory(&process_info_, sizeof(process_info_));

    // Get the bundled OpenVPN path
    bundled_path_ = GetPluginDataPath();
    openvpn_executable_path_ = bundled_path_ + "\\openvpn.exe";

    // Extract bundled OpenVPN on first run
    if (!std::filesystem::exists(openvpn_executable_path_))
    {
      ExtractBundledOpenVPN();
    }
  }

  OpenVpnDartPlugin::~OpenVpnDartPlugin()
  {
    StopVPN();
    is_monitoring_ = false;
    if (monitor_thread_.joinable())
    {
      monitor_thread_.join();
    }
    if (log_thread_.joinable())
    {
      log_thread_.join();
    }

    if (pipe_read_)
      CloseHandle(pipe_read_);
    if (pipe_write_)
      CloseHandle(pipe_write_);
  }

  std::string OpenVpnDartPlugin::GetPluginDataPath()
  {
    // Get AppData Local path
    PWSTR path = nullptr;
    HRESULT hr = SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &path);

    std::string base_path;
    if (SUCCEEDED(hr))
    {
      std::wstring ws(path);
      int size_needed = WideCharToMultiByte(CP_UTF8, 0, ws.c_str(), (int)ws.length(), nullptr, 0, nullptr, nullptr);
      base_path.resize(size_needed);
      WideCharToMultiByte(CP_UTF8, 0, ws.c_str(), (int)ws.length(), &base_path[0], size_needed, nullptr, nullptr);
      CoTaskMemFree(path);
    }
    else
    {
      // Fallback
      char appdata[MAX_PATH];
      size_t size;
      if (getenv_s(&size, appdata, MAX_PATH, "LOCALAPPDATA") == 0 && size > 0)
      {
        base_path = appdata;
      }
      else
      {
        base_path = "C:\\ProgramData";
      }
    }

    std::string plugin_path = base_path + "\\OpenVPNDart";
    std::filesystem::create_directories(plugin_path);
    return plugin_path;
  }

  std::string OpenVpnDartPlugin::GetBundledOpenVPNPath()
  {
    // Get the DLL path where bundled resources are located
    HMODULE hModule = nullptr;
    GetModuleHandleExA(
        GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        (LPCSTR)&OpenVpnDartPlugin::RegisterWithRegistrar,
        &hModule);

    char path[MAX_PATH];
    GetModuleFileNameA(hModule, path, MAX_PATH);

    std::filesystem::path dll_path(path);
    return dll_path.parent_path().string() + "\\openvpn_bundle";
  }

  bool OpenVpnDartPlugin::ExtractBundledOpenVPN()
  {
    try
    {
      std::string source = GetBundledOpenVPNPath();
      std::string dest = bundled_path_;

      if (!std::filesystem::exists(source))
      {
        return false; // Bundle not found
      }

      // Copy all files from bundle to destination
      for (const auto &entry : std::filesystem::recursive_directory_iterator(source))
      {
        if (entry.is_regular_file())
        {
          std::filesystem::path relative = std::filesystem::relative(entry.path(), source);
          std::filesystem::path dest_file = std::filesystem::path(dest) / relative;

          std::filesystem::create_directories(dest_file.parent_path());
          std::filesystem::copy_file(entry.path(), dest_file,
                                     std::filesystem::copy_options::overwrite_existing);
        }
      }

      return true;
    }
    catch (const std::exception &)
    {
      return false;
    }
  }

  bool OpenVpnDartPlugin::IsTAPDriverInstalled()
  {
    // Check if TAP adapter exists in network adapters
    HKEY hKey;
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,
                      "SYSTEM\\CurrentControlSet\\Control\\Class\\{4D36E972-E325-11CE-BFC1-08002BE10318}",
                      0, KEY_READ, &hKey) == ERROR_SUCCESS)
    {

      DWORD index = 0;
      char subkey_name[256];
      DWORD subkey_name_size = sizeof(subkey_name);

      while (RegEnumKeyExA(hKey, index++, subkey_name, &subkey_name_size,
                           nullptr, nullptr, nullptr, nullptr) == ERROR_SUCCESS)
      {
        HKEY subkey;
        if (RegOpenKeyExA(hKey, subkey_name, 0, KEY_READ, &subkey) == ERROR_SUCCESS)
        {
          char component_id[256] = {0};
          DWORD size = sizeof(component_id);

          if (RegQueryValueExA(subkey, "ComponentId", nullptr, nullptr,
                               (LPBYTE)component_id, &size) == ERROR_SUCCESS)
          {
            std::string comp(component_id);
            if (comp.find("tap0901") != std::string::npos ||
                comp.find("wintun") != std::string::npos)
            {
              RegCloseKey(subkey);
              RegCloseKey(hKey);
              return true;
            }
          }
          RegCloseKey(subkey);
        }
        subkey_name_size = sizeof(subkey_name);
      }
      RegCloseKey(hKey);
    }
    return false;
  }

  bool OpenVpnDartPlugin::InstallTAPDriver()
  {
    // Run the TAP driver installer
    std::string installer_path = bundled_path_ + "\\tap-windows-installer.exe";

    if (!std::filesystem::exists(installer_path))
    {
      return false;
    }

    SHELLEXECUTEINFOA sei = {0};
    sei.cbSize = sizeof(sei);
    sei.fMask = SEE_MASK_NOCLOSEPROCESS;
    sei.lpVerb = "runas"; // Request elevation
    sei.lpFile = installer_path.c_str();
    sei.lpParameters = "/S"; // Silent install
    sei.nShow = SW_HIDE;

    if (!ShellExecuteExA(&sei))
    {
      return false;
    }

    if (sei.hProcess)
    {
      WaitForSingleObject(sei.hProcess, INFINITE);
      CloseHandle(sei.hProcess);
    }

    return IsTAPDriverInstalled();
  }

  std::string OpenVpnDartPlugin::GetTAPAdapterName()
  {
    // Get the name of the TAP adapter
    HKEY hKey;
    std::string adapter_name = "TAP-Windows Adapter V9";

    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,
                      "SYSTEM\\CurrentControlSet\\Control\\Network\\{4D36E972-E325-11CE-BFC1-08002BE10318}",
                      0, KEY_READ, &hKey) == ERROR_SUCCESS)
    {
      // Enumerate network adapters to find TAP
      DWORD index = 0;
      char subkey_name[256];
      DWORD subkey_name_size = sizeof(subkey_name);

      while (RegEnumKeyExA(hKey, index++, subkey_name, &subkey_name_size,
                           nullptr, nullptr, nullptr, nullptr) == ERROR_SUCCESS)
      {
        std::string connection_key = std::string(subkey_name) + "\\Connection";
        HKEY conn_key;

        if (RegOpenKeyExA(hKey, connection_key.c_str(), 0, KEY_READ, &conn_key) == ERROR_SUCCESS)
        {
          char name[256] = {0};
          DWORD size = sizeof(name);

          if (RegQueryValueExA(conn_key, "Name", nullptr, nullptr,
                               (LPBYTE)name, &size) == ERROR_SUCCESS)
          {
            adapter_name = name;
            RegCloseKey(conn_key);
            break;
          }
          RegCloseKey(conn_key);
        }
        subkey_name_size = sizeof(subkey_name);
      }
      RegCloseKey(hKey);
    }

    return adapter_name;
  }

  void OpenVpnDartPlugin::HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  {

    const std::string &method = method_call.method_name();

    if (method == "initialize")
    {
      // Check if TAP driver is installed
      if (!IsTAPDriverInstalled())
      {
        // Try to install it
        if (!InstallTAPDriver())
        {
          result->Error("TAP_DRIVER_MISSING",
                        "TAP driver not installed and auto-install failed. Please run as administrator.");
          return;
        }
      }

      // Verify OpenVPN executable exists
      if (!std::filesystem::exists(openvpn_executable_path_))
      {
        if (!ExtractBundledOpenVPN())
        {
          result->Error("OPENVPN_NOT_FOUND",
                        "Failed to extract bundled OpenVPN");
          return;
        }
      }

      result->Success(flutter::EncodableValue(true));
    }
    else if (method == "connect")
    {
      const auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      if (!arguments)
      {
        result->Error("INVALID_ARGUMENT", "Arguments must be a map");
        return;
      }

      auto config_it = arguments->find(flutter::EncodableValue("config"));
      if (config_it == arguments->end())
      {
        result->Error("INVALID_ARGUMENT", "Missing 'config' parameter");
        return;
      }

      const std::string config = std::get<std::string>(config_it->second);

      try
      {
        StartVPN(config);
        result->Success(flutter::EncodableValue(true));
      }
      catch (const std::exception &e)
      {
        result->Error("CONNECTION_FAILED", e.what());
      }
    }
    else if (method == "disconnect")
    {
      try
      {
        StopVPN();
        result->Success(flutter::EncodableValue(true));
      }
      catch (const std::exception &e)
      {
        result->Error("DISCONNECTION_FAILED", e.what());
      }
    }
    else if (method == "status")
    {
      std::string status = GetCurrentStatus();
      result->Success(flutter::EncodableValue(status));
    }
    else if (method == "request_permission")
    {
      result->Success(flutter::EncodableValue(true));
    }
    else if (method == "checkTunnelConfiguration")
    {
      result->Success(flutter::EncodableValue(IsVPNRunning()));
    }
    else if (method == "removeTunnelConfiguration")
    {
      StopVPN();
      result->Success(flutter::EncodableValue(true));
    }
    else if (method == "setupTunnel")
    {
      result->Success(flutter::EncodableValue(true));
    }
    else
    {
      result->NotImplemented();
    }
  }

  void OpenVpnDartPlugin::StartVPN(const std::string &config)
  {
    if (is_connected_)
    {
      throw std::runtime_error("VPN is already connected");
    }

    // Create directories
    std::filesystem::path temp_dir = std::filesystem::path(bundled_path_) / "config";
    std::filesystem::create_directories(temp_dir);

    config_file_path_ = (temp_dir / "client.ovpn").string();
    log_file_path_ = (temp_dir / "openvpn.log").string();

    // Write config to file
    std::ofstream config_file(config_file_path_);
    if (!config_file.is_open())
    {
      throw std::runtime_error("Failed to create config file");
    }
    config_file << config;
    config_file.close();

    // Create pipe for reading OpenVPN output
    SECURITY_ATTRIBUTES sa = {0};
    sa.nLength = sizeof(SECURITY_ATTRIBUTES);
    sa.bInheritHandle = TRUE;
    sa.lpSecurityDescriptor = nullptr;

    if (!CreatePipe(&pipe_read_, &pipe_write_, &sa, 0))
    {
      throw std::runtime_error("Failed to create pipe");
    }

    SetHandleInformation(pipe_read_, HANDLE_FLAG_INHERIT, 0);

    // Prepare command line with detailed logging
    std::string command_line = "\"" + openvpn_executable_path_ + "\"";
    command_line += " --config \"" + config_file_path_ + "\"";
    command_line += " --log \"" + log_file_path_ + "\"";
    command_line += " --verb 3";
    command_line += " --dev-type tun";
    command_line += " --dev \"" + GetTAPAdapterName() + "\"";

    // Setup process creation
    STARTUPINFOA si = {0};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    si.hStdOutput = pipe_write_;
    si.hStdError = pipe_write_;
    si.wShowWindow = SW_HIDE;

    ZeroMemory(&process_info_, sizeof(process_info_));

    // Create the OpenVPN process
    BOOL success = CreateProcessA(
        nullptr,
        const_cast<char *>(command_line.c_str()),
        nullptr,
        nullptr,
        TRUE, // Inherit handles
        CREATE_NO_WINDOW,
        nullptr,
        nullptr,
        &si,
        &process_info_);

    if (!success)
    {
      DWORD error = GetLastError();
      CloseHandle(pipe_read_);
      CloseHandle(pipe_write_);
      pipe_read_ = nullptr;
      pipe_write_ = nullptr;
      throw std::runtime_error("Failed to start OpenVPN. Error: " + std::to_string(error));
    }

    process_handle_ = process_info_.hProcess;
    is_connected_ = true;

    // Update status
    {
      std::lock_guard<std::mutex> lock(status_mutex_);
      current_status_ = "connecting";
    }

    // Send initial status
    {
      std::lock_guard<std::mutex> lock(event_sink_mutex_);
      if (event_sink_)
      {
        event_sink_->Success(flutter::EncodableValue("connecting"));
      }
    }

    // Start monitoring threads
    if (!is_monitoring_)
    {
      is_monitoring_ = true;
      monitor_thread_ = std::thread(&OpenVpnDartPlugin::MonitorVPNStatus, this);
    }
  }

  void OpenVpnDartPlugin::StopVPN()
  {
    if (!is_connected_)
    {
      return;
    }

    is_connected_ = false;
    is_monitoring_ = false;

    // Terminate the process gracefully first
    if (process_handle_ != nullptr)
    {
      // Try graceful shutdown
      TerminateProcess(process_handle_, 0);
      WaitForSingleObject(process_handle_, 5000);
      CloseHandle(process_info_.hProcess);
      CloseHandle(process_info_.hThread);
      process_handle_ = nullptr;
      ZeroMemory(&process_info_, sizeof(process_info_));
    }

    // Close pipes
    if (pipe_write_)
    {
      CloseHandle(pipe_write_);
      pipe_write_ = nullptr;
    }

    // Update status
    {
      std::lock_guard<std::mutex> lock(status_mutex_);
      current_status_ = "disconnected";
    }

    // Send disconnected status
    {
      std::lock_guard<std::mutex> lock(event_sink_mutex_);
      if (event_sink_)
      {
        event_sink_->Success(flutter::EncodableValue("disconnected"));
      }
    }

    // Wait for threads
    if (monitor_thread_.joinable())
    {
      monitor_thread_.join();
    }
    if (log_thread_.joinable())
    {
      log_thread_.join();
    }
  }

  void OpenVpnDartPlugin::MonitorVPNStatus()
  {
    std::string last_status = "connecting";
    bool connection_established = false;

    while (is_monitoring_ && is_connected_)
    {
      // Check if process is still running
      if (process_handle_ != nullptr)
      {
        DWORD exit_code;
        if (GetExitCodeProcess(process_handle_, &exit_code))
        {
          if (exit_code != STILL_ACTIVE)
          {
            // Process terminated unexpectedly
            is_connected_ = false;
            std::lock_guard<std::mutex> lock(status_mutex_);
            current_status_ = "disconnected";

            std::lock_guard<std::mutex> sink_lock(event_sink_mutex_);
            if (event_sink_)
            {
              event_sink_->Success(flutter::EncodableValue("disconnected"));
            }
            break;
          }
        }
      }

      // Read log file to detect connection status
      if (std::filesystem::exists(log_file_path_))
      {
        std::ifstream log_file(log_file_path_);
        std::string line;
        std::string new_status = last_status;

        while (std::getline(log_file, line))
        {
          // Look for connection indicators
          if (line.find("Initialization Sequence Completed") != std::string::npos)
          {
            new_status = "connected";
            connection_established = true;
          }
          else if (line.find("CONNECTED") != std::string::npos &&
                   line.find("SUCCESS") != std::string::npos)
          {
            new_status = "connected";
            connection_established = true;
          }
          else if (line.find("CONNECTION_TIMEOUT") != std::string::npos ||
                   line.find("AUTH_FAILED") != std::string::npos)
          {
            new_status = "error";
          }
          else if (line.find("TCP/UDP: Preserving recently used remote") != std::string::npos)
          {
            new_status = "reconnecting";
          }
        }
        log_file.close();

        if (new_status != last_status)
        {
          last_status = new_status;
          std::lock_guard<std::mutex> lock(status_mutex_);
          current_status_ = new_status;

          std::lock_guard<std::mutex> sink_lock(event_sink_mutex_);
          if (event_sink_)
          {
            event_sink_->Success(flutter::EncodableValue(new_status));
          }
        }
      }

      Sleep(1000); // Check every second
    }

    is_monitoring_ = false;
  }

  std::string OpenVpnDartPlugin::GetCurrentStatus()
  {
    std::lock_guard<std::mutex> lock(status_mutex_);
    return current_status_;
  }

  bool OpenVpnDartPlugin::IsVPNRunning()
  {
    return is_connected_ && process_handle_ != nullptr;
  }

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OpenVpnDartPlugin::OnListenInternal(
      const flutter::EncodableValue *arguments,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> &&events)
  {
    std::lock_guard<std::mutex> lock(event_sink_mutex_);
    event_sink_ = std::move(events);

    if (event_sink_)
    {
      std::string status = GetCurrentStatus();
      event_sink_->Success(flutter::EncodableValue(status));
    }

    return nullptr;
  }

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OpenVpnDartPlugin::OnCancelInternal(const flutter::EncodableValue *arguments)
  {
    std::lock_guard<std::mutex> lock(event_sink_mutex_);
    event_sink_.reset();
    return nullptr;
  }

} // namespace openvpn_dart
