#include "openvpn3_integration.hpp"
#include "tun_packet_loop.hpp"
#include "openvpn_protocol.hpp"
#include <android/log.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <errno.h>
#include <fstream>
#include <sstream>
#include <regex>
#include <cstring>

#define LOG_TAG "OpenVPN3Integration"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)

OpenVPN3Client::OpenVPN3Client()
    : connected_(false),
      running_(false),
      proto_context_(nullptr),
      transport_(nullptr),
      udp_socket_(-1) {
    LOGI("OpenVPN3Client created");
}

OpenVPN3Client::~OpenVPN3Client() {
    disconnect();
    LOGI("OpenVPN3Client destroyed");
}

bool OpenVPN3Client::setConfig(const Config& config) {
    config_ = config;
    return parseConfig();
}

bool OpenVPN3Client::connect() {
    if (connected_) {
        LOGD("Already connected");
        return false;
    }
    
    running_ = true;
    connection_thread_ = std::make_unique<std::thread>(&OpenVPN3Client::connectionThread, this);
    
    return true;
}

void OpenVPN3Client::disconnect() {
    if (!running_) {
        return;
    }
    
    LOGI("Disconnecting");
    running_ = false;
    connected_ = false;
    
    if (udp_socket_ >= 0) {
        close(udp_socket_);
        udp_socket_ = -1;
    }
    
    if (connection_thread_ && connection_thread_->joinable()) {
        connection_thread_->join();
    }
    
    if (packet_thread_ && packet_thread_->joinable()) {
        packet_thread_->join();
    }
    
    notifyStatus("disconnected");
}

bool OpenVPN3Client::isConnected() const {
    return connected_;
}

void OpenVPN3Client::setStatusCallback(StatusCallback cb) {
    status_callback_ = cb;
}

void OpenVPN3Client::setLogCallback(LogCallback cb) {
    log_callback_ = cb;
}

OpenVPN3Client::Stats OpenVPN3Client::getStats() const {
    return stats_;
}

void OpenVPN3Client::connectionThread() {
    LOGI("Connection thread started");
    
    try {
        notifyStatus("connecting");
        
        // Step 1: Parse configuration
        if (!parseConfig()) {
            LOGE("Failed to parse config");
            notifyStatus("error");
            return;
        }
        log("Configuration parsed successfully");
        
        // Step 2: Setup transport (UDP socket)
        if (!setupTransport()) {
            LOGE("Failed to setup transport");
            notifyStatus("error");
            return;
        }
        log("Transport layer established");
        
        // Step 3: Setup tunnel
        if (!setupTunnel()) {
            LOGE("Failed to setup tunnel");
            notifyStatus("error");
            return;
        }
        log("Tunnel interface ready");
        
        // Step 4: Perform OpenVPN handshake
        if (!performHandshake()) {
            LOGE("Handshake failed");
            notifyStatus("error");
            return;
        }
        log("OpenVPN handshake completed");
        
        connected_ = true;
        notifyStatus("connected");
        log("VPN connection established");
        
        // Step 5: Start packet processing thread
        packet_thread_ = std::make_unique<std::thread>(&OpenVPN3Client::packetLoopThread, this);
        
        // Wait for disconnection
        while (running_ && connected_) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
        
    } catch (const std::exception& e) {
        LOGE("Connection thread exception: %s", e.what());
        notifyStatus("error");
    }
    
    connected_ = false;
    running_ = false;
    LOGI("Connection thread finished");
}

void OpenVPN3Client::packetLoopThread() {
    LOGI("Packet loop thread started");
    
    try {
        // Create packet loop handler
        packet_loop_ = std::make_unique<TunPacketLoop>(config_.tun_fd, udp_socket_);
        
        // Set up packet processing callback
        packet_loop_->setPacketCallback([this](const uint8_t* data, size_t len, bool from_tun) {
            if (from_tun) {
                // Packet from TUN (outgoing) - encrypt and send to server via UDP/TCP
                // TODO: Add OpenVPN encryption here
                ssize_t sent = send(udp_socket_, data, len, 0);
                if (sent < 0) {
                    LOGE("Failed to send packet to server: %s", strerror(errno));
                } else if (sent > 0) {
                    LOGI("Sent %zd bytes to VPN server", sent);
                }
            } else {
                // Packet from UDP/TCP (incoming) - decrypt and write to TUN
                // TODO: Add OpenVPN decryption here
                ssize_t written = write(config_.tun_fd, data, len);
                if (written < 0) {
                    LOGE("Failed to write packet to TUN: %s", strerror(errno));
                } else if (written > 0) {
                    LOGI("Wrote %zd bytes to TUN device", written);
                }
            }
        });
        
        // Process packets until disconnected
        while (running_ && connected_) {
            packet_loop_->processCycle();
        }
        
        // Get final statistics
        auto stats = packet_loop_->getStats();
        LOGI("Packet loop stats: packets_in=%llu, packets_out=%llu, bytes_in=%llu, bytes_out=%llu, errors=%llu",
             stats.packets_in, stats.packets_out, stats.bytes_in, stats.bytes_out, stats.errors);
        
    } catch (const std::exception& e) {
        LOGE("Packet loop exception: %s", e.what());
    }
    
    LOGI("Packet loop thread finished");
}

bool OpenVPN3Client::parseConfig() {
    LOGD("Parsing OpenVPN config");
    
    // TODO: Implement full config parser
    // For now, extract basic parameters using regex
    
    std::string& content = config_.config_content;
    
    // Extract remote server
    std::regex remote_regex(R"(remote\s+([^\s]+)\s+(\d+))");
    std::smatch match;
    
    if (std::regex_search(content, match, remote_regex)) {
        std::string server = match[1];
        std::string port = match[2];
        LOGI("Server: %s:%s", server.c_str(), port.c_str());
    } else {
        LOGE("No remote server found in config");
        return false;
    }
    
    // Extract protocol
    if (content.find("proto udp") != std::string::npos) {
        LOGD("Protocol: UDP");
    } else if (content.find("proto tcp") != std::string::npos) {
        LOGD("Protocol: TCP");
    }
    
    // Extract cipher
    std::regex cipher_regex(R"(cipher\s+([^\s]+))");
    if (std::regex_search(content, match, cipher_regex)) {
        LOGD("Cipher: %s", match[1].str().c_str());
    }
    
    return true;
}

bool OpenVPN3Client::setupTransport() {
    LOGD("Setting up transport layer");
    
    // Extract server, port and protocol from config
    std::string& content = config_.config_content;
    std::regex remote_regex(R"(remote\s+([^\s]+)\s+(\d+))");
    std::smatch match;
    
    // Detect protocol (TCP or UDP)
    bool use_tcp = (content.find("proto tcp") != std::string::npos);
    const char* proto_name = use_tcp ? "TCP" : "UDP";
    
    LOGI("Protocol detected: %s", proto_name);
    
    // Create socket based on protocol
    if (use_tcp) {
        udp_socket_ = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    } else {
        udp_socket_ = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    }
    
    if (udp_socket_ < 0) {
        LOGE("Failed to create %s socket: %s", proto_name, strerror(errno));
        return false;
    }
    
    // Set socket to non-blocking
    int flags = fcntl(udp_socket_, F_GETFL, 0);
    fcntl(udp_socket_, F_SETFL, flags | O_NONBLOCK);
    
    LOGI("%s socket created: fd=%d", proto_name, udp_socket_);
    
    if (std::regex_search(content, match, remote_regex)) {
        std::string server = match[1];
        std::string port_str = match[2];
        uint16_t port = static_cast<uint16_t>(std::stoul(port_str));
        
        LOGI("Connecting to VPN server: %s:%u", server.c_str(), port);
        
        // For now, use hardcoded IP - in production would need DNS resolution
        struct sockaddr_in server_addr = {};
        server_addr.sin_family = AF_INET;
        server_addr.sin_port = htons(port);
        
        // Try to parse as IP address
        if (inet_pton(AF_INET, server.c_str(), &server_addr.sin_addr) <= 0) {
            LOGW("Failed to parse server IP: %s (will retry with DNS later)", server.c_str());
            // Continue anyway - will handle errors when sending
        } else {
            int conn_result = ::connect(udp_socket_, (struct sockaddr*)&server_addr, sizeof(server_addr));
            
            if (use_tcp) {
                // For TCP non-blocking connect, EINPROGRESS is expected
                if (conn_result < 0 && errno != EINPROGRESS) {
                    LOGE("TCP connect failed: %s", strerror(errno));
                } else if (errno == EINPROGRESS) {
                    LOGI("TCP connection to %s:%u in progress...", server.c_str(), port);
                } else {
                    LOGI("TCP connection to %s:%u established", server.c_str(), port);
                }
            } else {
                // For UDP, connect just sets default destination
                if (conn_result < 0) {
                    LOGE("UDP connect failed: %s", strerror(errno));
                } else {
                    LOGI("UDP socket connected to %s:%u", server.c_str(), port);
                }
            }
        }
    } else {
        LOGW("Could not extract server from config");
    }
    
    return true;
}

bool OpenVPN3Client::setupTunnel() {
    LOGD("Setting up tunnel interface");
    
    if (config_.tun_fd < 0) {
        LOGE("Invalid TUN fd: %d", config_.tun_fd);
        return false;
    }
    
    // Set TUN to non-blocking
    int flags = fcntl(config_.tun_fd, F_GETFL, 0);
    fcntl(config_.tun_fd, F_SETFL, flags | O_NONBLOCK);
    
    LOGI("TUN interface ready: fd=%d", config_.tun_fd);
    return true;
}

bool OpenVPN3Client::performHandshake() {
    LOGD("Performing OpenVPN handshake");
    
    // First, wait for TCP connection to complete
    log("Waiting for TCP connection...");
    fd_set writefds;
    FD_ZERO(&writefds);
    FD_SET(udp_socket_, &writefds);
    
    struct timeval tv;
    tv.tv_sec = 5;
    tv.tv_usec = 0;
    
    int ret = select(udp_socket_ + 1, nullptr, &writefds, nullptr, &tv);
    if (ret <= 0 || !FD_ISSET(udp_socket_, &writefds)) {
        LOGE("TCP connection timeout or failed");
        return false;
    }
    
    // Check if connection was successful
    int error = 0;
    socklen_t len = sizeof(error);
    if (getsockopt(udp_socket_, SOL_SOCKET, SO_ERROR, &error, &len) < 0 || error != 0) {
        LOGE("TCP connection failed: %s", strerror(error));
        return false;
    }
    
    LOGI("TCP connection established!");
    log("TCP connection established");
    
    // Create handshake manager
    handshake_mgr_ = std::make_unique<OpenVPNProtocol::HandshakeManager>();
    
    if (!handshake_mgr_->init(config_.config_content, config_.username, config_.password)) {
        LOGE("Failed to initialize handshake manager");
        return false;
    }
    
    log("Initiating OpenVPN handshake...");
    
    // Send initial packets and wait for handshake completion
    const int MAX_HANDSHAKE_ATTEMPTS = 60;
    int attempts = 0;
    int packets_sent = 0;
    
    while (!handshake_mgr_->isComplete() && attempts < MAX_HANDSHAKE_ATTEMPTS && running_) {
        // Send pending packets
        while (handshake_mgr_->hasPendingData()) {
            auto packet = handshake_mgr_->getNextPacket();
            if (!packet.empty()) {
                ssize_t sent = send(udp_socket_, packet.data(), packet.size(), 0);
                if (sent > 0) {
                    packets_sent++;
                    LOGI("Sent handshake packet #%d: %zd bytes", packets_sent, sent);
                    
                    // Log first few bytes for debugging
                    std::string hex;
                    for (size_t i = 0; i < std::min(size_t(sent), size_t(16)); i++) {
                        char buf[4];
                        snprintf(buf, sizeof(buf), "%02x ", packet[i]);
                        hex += buf;
                    }
                    LOGI("Packet data: %s", hex.c_str());
                } else {
                    LOGE("Failed to send handshake packet: %s", strerror(errno));
                }
            }
        }
        
        // Wait for response with timeout
        fd_set readfds;
        FD_ZERO(&readfds);
        FD_SET(udp_socket_, &readfds);
        
        tv.tv_sec = 1;
        tv.tv_usec = 0;
        
        ret = select(udp_socket_ + 1, &readfds, nullptr, nullptr, &tv);
        if (ret > 0 && FD_ISSET(udp_socket_, &readfds)) {
            // Receive response
            uint8_t buffer[2048];
            ssize_t received = recv(udp_socket_, buffer, sizeof(buffer), 0);
            if (received > 0) {
                LOGI("Received handshake response: %zd bytes", received);
                
                // Log received bytes for debugging
                std::string hex;
                for (ssize_t i = 0; i < std::min(received, ssize_t(32)); i++) {
                    char buf[4];
                    snprintf(buf, sizeof(buf), "%02x ", buffer[i]);
                    hex += buf;
                }
                LOGI("Response data: %s", hex.c_str());
                
                handshake_mgr_->processPacket(buffer, received);
            } else if (received < 0) {
                if (errno != EAGAIN && errno != EWOULDBLOCK) {
                    LOGE("recv error: %s", strerror(errno));
                }
            } else {
                LOGW("Server closed connection");
                break;
            }
        }
        
        attempts++;
        
        // Resend RESET packet every 3 seconds if no response
        if (attempts % 3 == 0 && handshake_mgr_->getState() == OpenVPNProtocol::HandshakeManager::SEND_RESET) {
            LOGI("Resending RESET packet (attempt %d)", attempts / 3);
            // The packet is still in queue, it will be sent on next iteration
        }
        
        // Update status based on handshake state
        auto state = handshake_mgr_->getState();
        if (attempts % 5 == 0) {
            if (state == OpenVPNProtocol::HandshakeManager::TLS_HANDSHAKE) {
                log("TLS handshake in progress...");
            } else if (state == OpenVPNProtocol::HandshakeManager::WAIT_PUSH_REPLY) {
                log("Waiting for server configuration...");
            }
        }
    }
    
    if (handshake_mgr_->isComplete()) {
        log("Handshake completed successfully!");
        return true;
    } else {
        LOGE("Handshake failed or timed out. State: %d", handshake_mgr_->getState());
        log("Handshake failed: " + handshake_mgr_->getError());
        return false;
    }
}

void OpenVPN3Client::processPackets() {
    // This is now handled by TunPacketLoop
    if (packet_loop_) {
        auto stats = packet_loop_->getStats();
        stats_.bytes_in = stats.bytes_in;
        stats_.bytes_out = stats.bytes_out;
    }
}

void OpenVPN3Client::notifyStatus(const std::string& status) {
    if (status_callback_) {
        status_callback_(status);
    }
}

void OpenVPN3Client::log(const std::string& message) {
    LOGD("%s", message.c_str());
    if (log_callback_) {
        log_callback_(message);
    }
}
