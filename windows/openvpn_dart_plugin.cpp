#include "openvpn_dart_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <shlobj.h>
#include <tlhelp32.h>
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

    // Extract bundled OpenVPN on first run or if files are missing
    std::string tap_installer = bundled_path_ + "\\tap-windows-installer.exe";
    if (!std::filesystem::exists(openvpn_executable_path_) ||
        !std::filesystem::exists(tap_installer))
    {
      ExtractBundledOpenVPN();
    }

    // Check for existing OpenVPN connection
    CheckExistingConnection();
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
    std::string bundle_subdir = dll_path.parent_path().string() + "\\openvpn_bundle";
    std::string dll_dir = dll_path.parent_path().string();

    // Check if openvpn_bundle subdirectory exists, otherwise use DLL directory
    if (std::filesystem::exists(bundle_subdir))
    {
      return bundle_subdir;
    }
    return dll_dir;
  }

  bool OpenVpnDartPlugin::ExtractBundledOpenVPN()
  {
    try
    {
      std::string source = GetBundledOpenVPNPath();
      std::string dest = bundled_path_;

      OutputDebugStringA(("Extracting from: " + source).c_str());
      OutputDebugStringA(("Extracting to: " + dest).c_str());

      if (!std::filesystem::exists(source))
      {
        OutputDebugStringA("Source bundle not found!");
        return false; // Bundle not found
      }

      // Copy all files from bundle to destination
      int file_count = 0;
      for (const auto &entry : std::filesystem::recursive_directory_iterator(source))
      {
        if (entry.is_regular_file())
        {
          std::filesystem::path relative = std::filesystem::relative(entry.path(), source);
          std::filesystem::path dest_file = std::filesystem::path(dest) / relative;

          std::filesystem::create_directories(dest_file.parent_path());
          std::filesystem::copy_file(entry.path(), dest_file,
                                     std::filesystem::copy_options::overwrite_existing);
          file_count++;
          OutputDebugStringA(("Copied: " + dest_file.string()).c_str());
        }
      }

      OutputDebugStringA(("Extracted " + std::to_string(file_count) + " files").c_str());
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
      std::string error_details = "";
      bool tap_installed = IsTAPDriverInstalled();

      if (!tap_installed)
      {
        std::string installer_path = bundled_path_ + "\\tap-windows-installer.exe";
        error_details += "TAP driver not found. ";
        error_details += "Installer path: " + installer_path + " ";
        error_details += std::filesystem::exists(installer_path) ? "(exists) " : "(missing) ";
        error_details += "Bundled path: " + bundled_path_ + " ";

        // Try to install it
        if (std::filesystem::exists(installer_path))
        {
          if (!InstallTAPDriver())
          {
            error_details += "Auto-install failed. ";
          }
          else
          {
            tap_installed = true;
          }
        }
      }

      if (!tap_installed)
      {
        result->Error("TAP_DRIVER_MISSING",
                      "TAP driver required but not available. " + error_details +
                          "Please install TAP-Windows manually or ensure app runs with admin rights.");
        return;
      }

      // Verify OpenVPN executable exists
      if (!std::filesystem::exists(openvpn_executable_path_))
      {
        if (!ExtractBundledOpenVPN())
        {
          result->Error("OPENVPN_NOT_FOUND",
                        "Failed to extract bundled OpenVPN from: " + GetBundledOpenVPNPath());
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

      try
      {
        const std::string config = std::get<std::string>(config_it->second);
        OutputDebugStringA(("Config length: " + std::to_string(config.length())).c_str());

        StartVPN(config);
        result->Success(flutter::EncodableValue(true));
      }
      catch (const std::bad_variant_access &)
      {
        result->Error("INVALID_ARGUMENT", "Config parameter must be a string");
      }
      catch (const std::exception &e)
      {
        std::string error_msg = e.what();
        OutputDebugStringA(("StartVPN exception: " + error_msg).c_str());

        // Try to extract just the exit code if it's there
        std::string simple_msg = "OpenVPN failed to start";
        size_t code_pos = error_msg.find("code ");
        if (code_pos != std::string::npos)
        {
          size_t end_pos = error_msg.find_first_not_of("0123456789", code_pos + 5);
          if (end_pos != std::string::npos)
          {
            simple_msg = "OpenVPN exited with code " + error_msg.substr(code_pos + 5, end_pos - (code_pos + 5));
          }
        }

        result->Error("CONNECTION_FAILED", simple_msg);
      }
      catch (...)
      {
        result->Error("CONNECTION_FAILED", "Unknown error starting VPN");
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
      // On Windows, check if OpenVPN executable and TAP driver are available
      bool configured = std::filesystem::exists(openvpn_executable_path_) &&
                        IsTAPDriverInstalled();
      result->Success(flutter::EncodableValue(configured));
    }
    else if (method == "removeTunnelConfiguration")
    {
      StopVPN();
      result->Success(flutter::EncodableValue(true));
    }
    else if (method == "setupTunnel")
    {
      // On Windows, ensure OpenVPN is extracted and TAP driver is installed
      bool setup_success = true;

      if (!std::filesystem::exists(openvpn_executable_path_))
      {
        setup_success = ExtractBundledOpenVPN();
      }

      if (setup_success && !IsTAPDriverInstalled())
      {
        setup_success = InstallTAPDriver();
      }

      result->Success(flutter::EncodableValue(setup_success));
    }
    else
    {
      result->NotImplemented();
    }
  }

  void OpenVpnDartPlugin::StartVPN(const std::string &config)
  {
    // Ensure previous connection is fully stopped
    if (is_connected_ || is_monitoring_)
    {
      OutputDebugStringA("Stopping previous VPN connection before starting new one");
      is_monitoring_ = false;
      is_connected_ = false;

      // Wait for monitoring thread to exit
      if (monitor_thread_.joinable())
      {
        OutputDebugStringA("Waiting for monitor thread to join...");
        monitor_thread_.join();
        OutputDebugStringA("Monitor thread joined");
      }

      // Now call StopVPN to clean up process
      StopVPN();
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
    command_line += " --route-method exe";            // Use external routing method for Windows
    command_line += " --route-delay 2";               // Give Windows time to set up routes
    command_line += " --windows-driver tap-windows6"; // Use TAP-Windows6 driver

    OutputDebugStringA(("Starting OpenVPN with command: " + command_line).c_str());
    OutputDebugStringA(("Log file path: " + log_file_path_).c_str());

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
      std::string error_msg = "Failed to start OpenVPN. Error code: " + std::to_string(error);
      if (error == 740)
      {
        error_msg += " (Elevation required)";
      }
      else if (error == 2)
      {
        error_msg += " (File not found: " + openvpn_executable_path_ + ")";
      }
      OutputDebugStringA(error_msg.c_str());
      CloseHandle(pipe_read_);
      CloseHandle(pipe_write_);
      pipe_read_ = nullptr;
      pipe_write_ = nullptr;
      throw std::runtime_error(error_msg);
    }

    OutputDebugStringA("OpenVPN process created successfully");
    process_handle_ = process_info_.hProcess;
    is_connected_ = true;

    // Check if process is still running and look for early errors
    DWORD exit_code;
    Sleep(500); // Give it a moment to start and write logs

    bool process_exited = false;
    if (GetExitCodeProcess(process_handle_, &exit_code) && exit_code != STILL_ACTIVE)
    {
      process_exited = true;
      std::string exit_msg = "OpenVPN process exited with code " + std::to_string(exit_code);
      OutputDebugStringA(exit_msg.c_str());

      // Try to read error from log file
      if (std::filesystem::exists(log_file_path_))
      {
        std::ifstream log_file(log_file_path_);
        std::string line, error_detail;
        while (std::getline(log_file, line))
        {
          if (line.find("AUTH_FAILED") != std::string::npos ||
              line.find("ERROR") != std::string::npos ||
              line.find("FATAL") != std::string::npos)
          {
            error_detail = line;
          }
        }
        log_file.close();

        if (!error_detail.empty())
        {
          // Sanitize the error message
          for (char &c : error_detail)
          {
            if (static_cast<unsigned char>(c) > 127)
            {
              c = '?';
            }
          }
          exit_msg += ": " + error_detail;
        }
      }

      OutputDebugStringA(("Full error: " + exit_msg).c_str());

      // Process already exited - this is an error
      is_connected_ = false;
      CloseHandle(process_info_.hProcess);
      CloseHandle(process_info_.hThread);
      CloseHandle(pipe_read_);
      CloseHandle(pipe_write_);
      pipe_read_ = nullptr;
      pipe_write_ = nullptr;
      process_handle_ = nullptr;
      throw std::runtime_error(exit_msg);
    }

    // Update status and send to Flutter immediately
    {
      std::lock_guard<std::mutex> lock(status_mutex_);
      current_status_ = "connecting";
    }

    // Send initial connecting status to Flutter
    {
      std::lock_guard<std::mutex> lock(event_sink_mutex_);
      if (event_sink_)
      {
        OutputDebugStringA("Sending 'connecting' status to Flutter");
        event_sink_->Success(flutter::EncodableValue("connecting"));
      }
      else
      {
        OutputDebugStringA("Warning: event_sink is null, cannot send connecting status");
      }
    }

    // Start monitoring thread
    if (!is_monitoring_)
    {
      is_monitoring_ = true;
      monitor_thread_ = std::thread(&OpenVpnDartPlugin::MonitorVPNStatus, this);
    }
  }

  void OpenVpnDartPlugin::StopVPN()
  {
    // Send disconnecting status
    {
      std::lock_guard<std::mutex> lock(status_mutex_);
      current_status_ = "disconnecting";
    }

    {
      std::lock_guard<std::mutex> lock(event_sink_mutex_);
      if (event_sink_)
      {
        OutputDebugStringA("Sending 'disconnecting' status to Flutter");
        event_sink_->Success(flutter::EncodableValue("disconnecting"));
      }
    }

    // Give the disconnecting status time to be processed
    Sleep(100);

    // Terminate the process gracefully first
    if (process_handle_ != nullptr)
    {
      // Try graceful shutdown
      TerminateProcess(process_handle_, 0);
      WaitForSingleObject(process_handle_, 5000);
      CloseHandle(process_info_.hProcess);
      if (process_info_.hThread != nullptr)
      {
        CloseHandle(process_info_.hThread);
      }
      process_handle_ = nullptr;
      ZeroMemory(&process_info_, sizeof(process_info_));
    }

    // Close pipes
    if (pipe_write_)
    {
      CloseHandle(pipe_write_);
      pipe_write_ = nullptr;
    }

    // Set flags to false to stop monitoring thread
    is_connected_ = false;
    is_monitoring_ = false;

    // Wait for threads to finish
    if (monitor_thread_.joinable())
    {
      monitor_thread_.join();
    }
    if (log_thread_.joinable())
    {
      log_thread_.join();
    }

    // Update status to disconnected
    {
      std::lock_guard<std::mutex> lock(status_mutex_);
      current_status_ = "disconnected";
    }

    // Send disconnected status
    {
      std::lock_guard<std::mutex> lock(event_sink_mutex_);
      if (event_sink_)
      {
        OutputDebugStringA("Sending 'disconnected' status to Flutter");
        event_sink_->Success(flutter::EncodableValue("disconnected"));
      }
    }
  }

  void OpenVpnDartPlugin::MonitorVPNStatus()
  {
    OutputDebugStringA("MonitorVPNStatus thread started");
    std::string last_status = "";
    bool connection_established = false;

    // Give the "connecting" status time to be sent and processed
    Sleep(100);

    while (is_monitoring_ && is_connected_)
    {
      // Check if we should stop monitoring
      if (!is_monitoring_ || !is_connected_)
      {
        OutputDebugStringA("Monitoring flags set to false, exiting thread");
        break;
      }

      // Check if process is still running
      if (process_handle_ != nullptr)
      {
        DWORD exit_code;
        if (GetExitCodeProcess(process_handle_, &exit_code))
        {
          if (exit_code != STILL_ACTIVE)
          {
            OutputDebugStringA(("Process exited with code " + std::to_string(exit_code)).c_str());
            // Process terminated unexpectedly
            is_connected_ = false;
            {
              std::lock_guard<std::mutex> lock(status_mutex_);
              current_status_ = "disconnected";
            }

            {
              std::lock_guard<std::mutex> sink_lock(event_sink_mutex_);
              if (event_sink_)
              {
                event_sink_->Success(flutter::EncodableValue("disconnected"));
              }
            }
            break;
          }
        }
      }

      // Read log file to detect connection status
      if (std::filesystem::exists(log_file_path_))
      {
        try
        {
          std::ifstream log_file(log_file_path_);
          if (!log_file.is_open())
          {
            OutputDebugStringA("Failed to open log file");
          }
          else
          {
            std::string line;
            std::string new_status = "connecting"; // Default to connecting if no specific state found

            while (std::getline(log_file, line))
            {
              // Look for connection indicators
              if (line.find("Initialization Sequence Completed") != std::string::npos)
              {
                new_status = "connected";
                connection_established = true;
                OutputDebugStringA("VPN connection established!");
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
                OutputDebugStringA("VPN connection error detected");
              }
              else if (line.find("TCP/UDP: Preserving recently used remote") != std::string::npos)
              {
                // During initial connection, this is part of connecting process
                // Only treat as reconnecting if we were already connected
                if (connection_established)
                {
                  new_status = "connecting"; // Treat reconnect as connecting
                  OutputDebugStringA("VPN reconnecting");
                }
              }
            }
            log_file.close();

            if (new_status != last_status)
            {
              last_status = new_status;
              OutputDebugStringA(("Status changed to: " + new_status).c_str());

              {
                std::lock_guard<std::mutex> lock(status_mutex_);
                current_status_ = new_status;
              }

              {
                std::lock_guard<std::mutex> sink_lock(event_sink_mutex_);
                if (event_sink_)
                {
                  event_sink_->Success(flutter::EncodableValue(new_status));
                }
                else
                {
                  OutputDebugStringA("event_sink is null, cannot send status update");
                }
              }
            }
          }
        }
        catch (const std::exception &e)
        {
          OutputDebugStringA(("Error reading log file: " + std::string(e.what())).c_str());
        }
      }

      Sleep(1000); // Check every second
    }

    OutputDebugStringA("MonitorVPNStatus thread exiting");
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

  void OpenVpnDartPlugin::CheckExistingConnection()
  {
    OutputDebugStringA("Checking for existing OpenVPN connection...");

    // Set up log file path
    log_file_path_ = bundled_path_ + "\\config\\openvpn.log";

    // Check if log file exists and has recent "Initialization Sequence Completed" message
    if (std::filesystem::exists(log_file_path_))
    {
      try
      {
        std::ifstream log_file(log_file_path_);
        if (log_file.is_open())
        {
          std::string line;
          bool found_connected = false;
          bool found_exit = false;

          while (std::getline(log_file, line))
          {
            if (line.find("Initialization Sequence Completed") != std::string::npos)
            {
              found_connected = true;
            }
            else if (line.find("process exiting") != std::string::npos ||
                     line.find("SIGTERM") != std::string::npos)
            {
              found_exit = true;
            }
          }
          log_file.close();

          // If we found connection but no exit, check if process is still running
          if (found_connected && !found_exit)
          {
            // Try to find the OpenVPN process by name
            HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
            if (snapshot != INVALID_HANDLE_VALUE)
            {
              PROCESSENTRY32 pe32;
              pe32.dwSize = sizeof(PROCESSENTRY32);

              if (Process32First(snapshot, &pe32))
              {
                do
                {
                  // Convert wide string to narrow string
                  char processName[MAX_PATH];
                  WideCharToMultiByte(CP_ACP, 0, pe32.szExeFile, -1, processName, MAX_PATH, NULL, NULL);

                  if (strcmp(processName, "openvpn.exe") == 0)
                  {
                    // Found OpenVPN process - check if it's ours by command line
                    HANDLE hProcess = OpenProcess(PROCESS_QUERY_INFORMATION | SYNCHRONIZE | PROCESS_TERMINATE, FALSE, pe32.th32ProcessID);
                    if (hProcess != nullptr)
                    {
                      OutputDebugStringA(("Found existing OpenVPN process with PID " + std::to_string(pe32.th32ProcessID)).c_str());

                      // Set up our state to monitor this process
                      process_handle_ = hProcess;
                      ZeroMemory(&process_info_, sizeof(process_info_));
                      process_info_.hProcess = hProcess;
                      process_info_.hThread = nullptr; // We don't have the thread handle for existing process
                      process_info_.dwProcessId = pe32.th32ProcessID;
                      is_connected_ = true;

                      {
                        std::lock_guard<std::mutex> lock(status_mutex_);
                        current_status_ = "connected";
                      }

                      // Start monitoring thread
                      if (!is_monitoring_)
                      {
                        is_monitoring_ = true;
                        monitor_thread_ = std::thread(&OpenVpnDartPlugin::MonitorVPNStatus, this);
                      }

                      OutputDebugStringA("Attached to existing OpenVPN connection");
                      break;
                    }
                  }
                } while (Process32Next(snapshot, &pe32));
              }
              CloseHandle(snapshot);
            }
          }
        }
      }
      catch (const std::exception &e)
      {
        OutputDebugStringA(("Error checking existing connection: " + std::string(e.what())).c_str());
      }
    }

    if (!is_connected_)
    {
      OutputDebugStringA("No existing OpenVPN connection found");
    }
  }

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OpenVpnDartPlugin::OnListenInternal(
      const flutter::EncodableValue *arguments,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> &&events)
  {
    std::lock_guard<std::mutex> lock(event_sink_mutex_);
    event_sink_ = std::move(events);

    // Always send current status when stream listener attaches
    if (event_sink_)
    {
      std::string status = GetCurrentStatus();
      OutputDebugStringA(("Sending initial status on stream listen: " + status).c_str());
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
