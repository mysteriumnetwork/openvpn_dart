#include "include/openvpn_dart/openvpn_dart_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "openvpn_dart_plugin.h"

void OpenvpnDartPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  openvpn_dart::OpenvpnDartPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
