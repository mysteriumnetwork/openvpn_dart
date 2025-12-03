#ifndef FLUTTER_PLUGIN_OPENVPN_DART_PLUGIN_H_
#define FLUTTER_PLUGIN_OPENVPN_DART_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>

#include <memory>
#include <string>
#include <thread>
#include <atomic>
#include <mutex>

namespace openvpn_dart
{

    class OpenVpnDartPlugin : public flutter::Plugin
    {
    public:
        static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

        OpenVpnDartPlugin(flutter::PluginRegistrarWindows *registrar);

        virtual ~OpenVpnDartPlugin();

        // Disallow copy and assign.
        OpenVpnDartPlugin(const OpenVpnDartPlugin &) = delete;
        OpenVpnDartPlugin &operator=(const OpenVpnDartPlugin &) = delete;

        // Called when a method is called on the plugin channel from Dart.
        void HandleMethodCall(
            const flutter::MethodCall<flutter::EncodableValue> &method_call,
            std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    private:
        // OpenVPN process management
        void StartVPN(const std::string &config);
        void StopVPN();
        void MonitorVPNStatus();
        std::string GetCurrentStatus();
        bool IsVPNRunning();

        // TAP driver management
        bool IsTAPDriverInstalled();
        bool InstallTAPDriver();
        std::string GetTAPAdapterName();

        // Bundled OpenVPN setup
        bool ExtractBundledOpenVPN();
        std::string GetBundledOpenVPNPath();
        std::string GetPluginDataPath();

        // Event channel handlers
        std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
        OnListenInternal(
            const flutter::EncodableValue *arguments,
            std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> &&events);

        std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
        OnCancelInternal(const flutter::EncodableValue *arguments);

        // Plugin registrar
        flutter::PluginRegistrarWindows *registrar_;

        // Event sink for status updates
        std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
        std::mutex event_sink_mutex_;

        // OpenVPN process handle
        PROCESS_INFORMATION process_info_;
        HANDLE process_handle_;
        HANDLE pipe_read_;
        HANDLE pipe_write_;
        std::atomic<bool> is_connected_;
        std::atomic<bool> is_monitoring_;
        std::thread monitor_thread_;
        std::thread log_thread_;
        std::string current_status_;
        std::mutex status_mutex_;

        // Paths
        std::string config_file_path_;
        std::string openvpn_executable_path_;
        std::string bundled_path_;
        std::string log_file_path_;
    };

} // namespace openvpn_dart

#endif // FLUTTER_PLUGIN_OPENVPN_DART_PLUGIN_H_
