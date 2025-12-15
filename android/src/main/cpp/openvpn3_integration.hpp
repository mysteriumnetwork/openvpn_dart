#ifndef OPENVPN3_INTEGRATION_HPP
#define OPENVPN3_INTEGRATION_HPP

#include <string>
#include <memory>
#include <functional>
#include <thread>
#include <atomic>

// Forward declarations
class TunPacketLoop;

namespace OpenVPNProtocol {
    class HandshakeManager;
}

// Simplified OpenVPN3 client wrapper for Android integration
class OpenVPN3Client {
public:
    using StatusCallback = std::function<void(const std::string&)>;
    using LogCallback = std::function<void(const std::string&)>;
    
    struct Config {
        std::string config_content;
        std::string username;
        std::string password;
        int tun_fd;
    };
    
    struct Stats {
        uint64_t bytes_in = 0;
        uint64_t bytes_out = 0;
    };
    
    OpenVPN3Client();
    ~OpenVPN3Client();
    
    // Configuration
    bool setConfig(const Config& config);
    
    // Connection control
    bool connect();
    void disconnect();
    bool isConnected() const;
    
    // Callbacks
    void setStatusCallback(StatusCallback cb);
    void setLogCallback(LogCallback cb);
    
    // Statistics
    Stats getStats() const;
    
private:
    void connectionThread();
    void packetLoopThread();
    
    bool parseConfig();
    bool setupTransport();
    bool setupTunnel();
    bool performHandshake();
    void processPackets();
    
    void notifyStatus(const std::string& status);
    void log(const std::string& message);
    
    Config config_;
    std::atomic<bool> connected_;
    std::atomic<bool> running_;
    
    StatusCallback status_callback_;
    LogCallback log_callback_;
    
    Stats stats_;
    
    std::unique_ptr<std::thread> connection_thread_;
    std::unique_ptr<std::thread> packet_thread_;
    
    // OpenVPN3 Core objects (to be implemented)
    void* proto_context_;  // ProtoContext
    void* transport_;      // Transport layer
    int udp_socket_;
    
    std::unique_ptr<TunPacketLoop> packet_loop_;
    std::unique_ptr<OpenVPNProtocol::HandshakeManager> handshake_mgr_;
};

#endif // OPENVPN3_INTEGRATION_HPP
