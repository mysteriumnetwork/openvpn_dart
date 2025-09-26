import NetworkExtension
import os

#if os(iOS)
    import Flutter
    import UIKit
#elseif os(macOS)
    import Cocoa
    import FlutterMacOS
#else
    #error("Unsupported platform")
#endif

public class OpenvpnDartPlugin: NSObject, FlutterPlugin {
    private static var utils: VPNUtils! = VPNUtils()

    private static let EVENT_CHANNEL_VPN_STATUS =
        "id.mysteriumvpn.openvpn_flutter/vpnstatus"
    private static let METHOD_CHANNEL_VPN_CONTROL =
        "id.mysteriumvpn.openvpn_flutter/vpncontrol"

    public static var status: FlutterEventSink?
    private var initialized: Bool = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = OpenvpnDartPlugin()
        instance.onRegister(registrar)
    }

    public func onRegister(_ registrar: FlutterPluginRegistrar) {
        #if os(iOS)
            let messenger = registrar.messenger()
        #else
            let messenger = registrar.messenger
        #endif

        let vpnControlM = FlutterMethodChannel(
            name: OpenvpnDartPlugin.METHOD_CHANNEL_VPN_CONTROL,
            binaryMessenger: messenger)
        let vpnStatusE = FlutterEventChannel(
            name: OpenvpnDartPlugin.EVENT_CHANNEL_VPN_STATUS,
            binaryMessenger: messenger)

        vpnStatusE.setStreamHandler(StatusHandler())
        vpnControlM.setMethodCallHandler {
            (call: FlutterMethodCall, result: @escaping FlutterResult) in

            switch call.method {
            case "initialize":
                guard let args = call.arguments as? [String: Any],
                      let bundleId = args["providerBundleIdentifier"] as? String,
                      let description = args["localizedDescription"] as? String
                else {
                    result(FlutterError(
                        code: "-2",
                        message: "Initialization parameters missing",
                        details: nil))
                    return
                }

                OpenvpnDartPlugin.utils.providerBundleIdentifier = bundleId
                OpenvpnDartPlugin.utils.localizedDescription = description

                OpenvpnDartPlugin.utils.loadProviderManager { err in
                    if let error = err {
                        os_log("[PLUGIN] loadProviderManager failed: %@", error.localizedDescription)
                        result(FlutterError(code: "-3", message: error.localizedDescription, details: error.localizedDescription))
                    } else {
                        self.initialized = true
                        os_log("[PLUGIN] loadProviderManager succeeded")
                        result(OpenvpnDartPlugin.utils.currentStatus())
                    }
                }

            case "checkTunnelConfiguration":
                OpenvpnDartPlugin.utils.checkTunnelConfiguration { manager in
                    if let _ = manager {
                        os_log("[PLUGIN] Tunnel is already configured")
                        result(true)
                    } else {
                        os_log("[PLUGIN] Tunnel is not configured")
                        result(false)
                    }
                }

            case "setupTunnel":
                guard self.initialized else {
                    result(FlutterError(code: "-1", message: "VPN engine must be initialized", details: nil))
                    return
                }
                OpenvpnDartPlugin.utils.setupTunnel { error in
                    if let err = error {
                        os_log("[PLUGIN] setupTunnel failed: %@", err.localizedDescription)
                        result(FlutterError(code: "98", message: "Failed to setup tunnel", details: err.localizedDescription))
                    } else {
                        os_log("[PLUGIN] setupTunnel succeeded")
                        result(OpenvpnDartPlugin.utils.currentStatus())
                    }
                }

            case "connect":
                guard self.initialized else {
                    result(FlutterError(code: "-1", message: "VPN engine must be initialized", details: nil))
                    return
                }

                guard let config = (call.arguments as? [String: Any])?["config"] as? String else {
                    result(FlutterError(code: "-2", message: "Config is empty or nil", details: nil))
                    return
                }

                OpenvpnDartPlugin.utils.configureVPN(config: config) { error in
                    if let err = error {
                        os_log("[PLUGIN] configureVPN failed: %@", err.localizedDescription)
                        result(FlutterError(code: "99", message: "Failed to start VPN", details: err.localizedDescription))
                    } else {
                        os_log("[PLUGIN] configureVPN succeeded")
                        result(nil)
                    }
                }

            case "disconnect":
                os_log("[PLUGIN] stopVPN called from Flutter")
                OpenvpnDartPlugin.utils.stopVPN()
                result(nil)

            case "dispose":
                self.initialized = false
                result(nil)

            case "removeTunnelConfiguration":
                OpenvpnDartPlugin.utils.removeTunnelConfiguration { error in
                    if let err = error {
                        os_log("[PLUGIN] removeTunnelConfiguration failed: %@", err.localizedDescription)
                        result(FlutterError(code: "96", message: "Failed to remove tunnel", details: err.localizedDescription))
                    } else {
                        os_log("[PLUGIN] removeTunnelConfiguration succeeded")
                        result(true)
                    }
                }

            case "status":
                result(OpenvpnDartPlugin.utils.currentStatus())

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    class StatusHandler: NSObject, FlutterStreamHandler {
        func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
            OpenvpnDartPlugin.utils.status = events
            return nil
        }

        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            OpenvpnDartPlugin.utils.status = nil
            return nil
        }
    }
}

#if os(iOS) || os(macOS)
class VPNUtils {
    var providerManager: NETunnelProviderManager?
    var providerBundleIdentifier: String?
    var localizedDescription: String?
    var status: FlutterEventSink?
    var vpnStatusObserver: NSObjectProtocol?

    func loadProviderManager(completion: @escaping (_ error: Error?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let err = error {
                os_log("[VPNUTILS] loadAllFromPreferences failed: %@", err.localizedDescription)
                completion(err)
            } else {
                self.providerManager = managers?.first
                os_log("[VPNUTILS] Provider manager loaded")
                completion(nil)
            }
        }
    }

    func currentStatus() -> String {
        guard let manager = providerManager else { return "disconnected" }
        return stringFromStatus(manager.connection.status)
    }

    private func stringFromStatus(_ status: NEVPNStatus) -> String {
        switch status {
        case .connected: return "connected"
        case .connecting: return "connecting"
        case .disconnected: return "disconnected"
        case .disconnecting: return "disconnecting"
        @unknown default: return "unknown"
        }
    }

    func checkTunnelConfiguration(result: @escaping (NETunnelProviderManager?) -> Void) {
        guard let bundleId = providerBundleIdentifier else {
            result(nil)
            return
        }
        Task {
            do {
                let managers = try await NETunnelProviderManager.loadAllFromPreferences()
                if let existingMgr = managers.first(where: {
                    ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == bundleId
                }) {
                    self.providerManager = existingMgr
                    result(existingMgr)
                } else {
                    result(nil)
                }
            } catch {
                result(nil)
            }
        }
    }

    func setupTunnel(completion: @escaping (_ error: Error?) -> Void) {
        // Only create a new tunnel if none exists
        checkTunnelConfiguration { existingManager in
            if let manager = existingManager {
                os_log("[VPNUTILS] Tunnel already configured, reusing existing")
                self.providerManager = manager
                completion(nil)
                return
            }

            os_log("[VPNUTILS] No existing tunnel, creating new one")
            guard let bundleId = self.providerBundleIdentifier else {
                completion(NSError(domain: "VPNUtils", code: -1, userInfo: [NSLocalizedDescriptionKey: "providerBundleIdentifier not set"]))
                return
            }

            let newManager = NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = bundleId
            proto.serverAddress = "127.0.0.1"
            proto.disconnectOnSleep = false

            newManager.protocolConfiguration = proto
            newManager.localizedDescription = self.localizedDescription
            newManager.isEnabled = true

            newManager.saveToPreferences { saveError in
                if let saveError = saveError {
                    os_log("[VPNUTILS] saveToPreferences failed: %@", saveError.localizedDescription)
                    completion(saveError)
                    return
                }

                // Reload and assign providerManager
                NETunnelProviderManager.loadAllFromPreferences { reloadManagers, reloadError in
                    if let reloadError = reloadError {
                        completion(reloadError)
                        return
                    }
                    self.providerManager = reloadManagers?.first
                    os_log("[VPNUTILS] Tunnel setup completed successfully")
                    completion(nil)
                }
            }
        }
    }

    func configureVPN(config: String, completion: @escaping (_ error: Error?) -> Void) {
        guard let existingManager = providerManager else {
            let err = NSError(domain: "VPN", code: -10, userInfo: [NSLocalizedDescriptionKey: "Tunnel not initialized. Call setupTunnel first."])
            completion(err)
            return
        }

        existingManager.loadFromPreferences { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                completion(error)
                return
            }

            guard let ovpnData = config.data(using: .utf8) else {
                completion(NSError(domain: "VPN", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode OpenVPN config"]))
                return
            }

            let tunnelProtocol = NETunnelProviderProtocol()
            tunnelProtocol.providerBundleIdentifier = self.providerBundleIdentifier
            tunnelProtocol.serverAddress = self.extractServerAddress(from: config)
            tunnelProtocol.disconnectOnSleep = false
            tunnelProtocol.providerConfiguration = ["config": ovpnData]

            self.providerManager?.protocolConfiguration = tunnelProtocol
            self.providerManager?.localizedDescription = self.localizedDescription
            self.providerManager?.isEnabled = true

            self.providerManager?.saveToPreferences { saveError in
                if let saveError = saveError {
                    completion(saveError)
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    do {
                        try self.providerManager?.connection.startVPNTunnel(options: [:])
                        self.observeStatus()
                        completion(nil)
                    } catch {
                        self.stopVPN()
                        completion(error)
                    }
                }
            }
        }
    }

    func stopVPN() {
        os_log("[VPNUTILS] Stopping VPN tunnel")
        providerManager?.connection.stopVPNTunnel()
    }

    private func extractServerAddress(from config: String) -> String {
        for line in config.components(separatedBy: .newlines) {
            if line.lowercased().hasPrefix("remote ") {
                let parts = line.components(separatedBy: " ")
                if parts.count >= 2 { return parts[1] }
            }
        }
        return "127.0.0.1"
    }

    private func observeStatus() {
        if let observer = vpnStatusObserver {
            NotificationCenter.default.removeObserver(observer, name: NSNotification.Name.NEVPNStatusDidChange, object: nil)
        }

        vpnStatusObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NEVPNStatusDidChange,
            object: providerManager?.connection,
            queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            self.status?(self.stringFromStatus(self.providerManager?.connection.status ?? .invalid))
            os_log("[VPNUTILS] VPN status changed: %@", self.stringFromStatus(self.providerManager?.connection.status ?? .invalid))
        }
    }

    func removeTunnelConfiguration(completion: @escaping (_ error: Error?) -> Void) {
        guard let manager = providerManager else {
            os_log("[VPNUTILS] No tunnel to remove")
            completion(nil)
            return
        }

        manager.removeFromPreferences { error in
            if let err = error {
                os_log("[VPNUTILS] Failed to remove tunnel: %@", err.localizedDescription)
                completion(err)
                return
            }

            os_log("[VPNUTILS] Tunnel removed from preferences")
            self.providerManager = nil
            completion(nil)
        }
    }
}
#endif
