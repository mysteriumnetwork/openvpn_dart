#include "openvpn_client.h"
#include "openvpn3_integration.hpp"
#include <android/log.h>
#include <cstring>
#include <thread>
#include <fstream>
#include <sstream>

#define LOG_TAG "OpenVPNClient"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Global client instance
static OpenVPNClient* g_client = nullptr;

// OpenVPNClient implementation
OpenVPNClient::OpenVPNClient()
    : is_connected(false),
      bytes_in(0),
      bytes_out(0),
      tun_fd_(-1),
      status_callback(nullptr),
      ovpn_client(new OpenVPN3Client()) {
    LOGI("OpenVPNClient instance created");
}

OpenVPNClient::~OpenVPNClient() {
    if (is_connected) {
        disconnect();
    }
    delete ovpn_client;
    LOGI("OpenVPNClient instance destroyed");
}

OpenVPNClient* OpenVPNClient::getInstance() {
    if (!g_client) {
        g_client = new OpenVPNClient();
    }
    return g_client;
}

bool OpenVPNClient::initialize() {
    LOGI("Initializing OpenVPN client");
    return true;
}

std::string OpenVPNClient::readConfigFile(const std::string& path) {
    std::ifstream file(path);
    if (!file.is_open()) {
        LOGE("Failed to open config file: %s", path.c_str());
        return "";
    }
    
    std::stringstream buffer;
    buffer << file.rdbuf();
    return buffer.str();
}

bool OpenVPNClient::connect(const std::string& config_path,
                           const std::string& username,
                           const std::string& password) {
    if (is_connected) {
        LOGD("Already connected");
        return false;
    }

    LOGI("Starting VPN connection with config: %s", config_path.c_str());

    try {
        config_path_ = config_path;
        username_ = username;
        password_ = password;

        // Start connection in separate thread
        std::thread conn_thread(&OpenVPNClient::connectionThread, this);
        conn_thread.detach();

        return true;
    } catch (const std::exception& e) {
        LOGE("Connection error: %s", e.what());
        return false;
    }
}

bool OpenVPNClient::disconnect() {
    if (!is_connected) {
        LOGD("Not connected");
        return false;
    }

    LOGI("Disconnecting VPN");
    is_connected = false;

    if (ovpn_client) {
        ovpn_client->disconnect();
    }

    if (status_callback) {
        status_callback("disconnecting");
    }

    return true;
}

void OpenVPNClient::connectionThread() {
    LOGD("Connection thread started");

    try {
        // Read config file
        std::string config_content = readConfigFile(config_path_);
        if (config_content.empty()) {
            LOGE("Empty config file");
            if (status_callback) status_callback("error");
            return;
        }
        
        LOGI("Config file loaded successfully");
        
        // Validate TUN fd
        if (tun_fd_ < 0) {
            LOGE("Invalid TUN file descriptor: %d", tun_fd_);
            if (status_callback) status_callback("error");
            return;
        }
        
        LOGI("TUN fd validated: %d", tun_fd_);
        
        // Configure OpenVPN3 client
        OpenVPN3Client::Config config;
        config.config_content = config_content;
        config.username = username_;
        config.password = password_;
        config.tun_fd = tun_fd_;
        
        // Setup callbacks
        ovpn_client->setStatusCallback([this](const std::string& status) {
            if (status == "connected") {
                is_connected = true;
            } else if (status == "disconnected" || status == "error") {
                is_connected = false;
            }
            if (status_callback) {
                status_callback(status.c_str());
            }
        });
        
        ovpn_client->setLogCallback([](const std::string& msg) {
            LOGD("OpenVPN3: %s", msg.c_str());
        });
        
        // Set configuration
        if (!ovpn_client->setConfig(config)) {
            LOGE("Failed to set config");
            if (status_callback) status_callback("error");
            return;
        }
        
        // Start connection
        if (!ovpn_client->connect()) {
            LOGE("Failed to start connection");
            if (status_callback) status_callback("error");
            return;
        }
        
        LOGI("OpenVPN3 client connection initiated");
        
        // Update stats periodically
        while (is_connected && ovpn_client->isConnected()) {
            std::this_thread::sleep_for(std::chrono::seconds(1));
            
            auto stats = ovpn_client->getStats();
            bytes_in = stats.bytes_in;
            bytes_out = stats.bytes_out;
        }

        LOGI("VPN connection closed");

    } catch (const std::exception& e) {
        LOGE("Connection thread error: %s", e.what());
        is_connected = false;
        if (status_callback) {
            status_callback("disconnected");
        }
    }
}

void OpenVPNClient::setTunFd(int fd) {
    tun_fd_ = fd;
    LOGI("TUN fd set to: %d", fd);
}

const char* OpenVPNClient::getVersion() const {
    return "OpenVPN3 Core (Infrastructure Ready - Protocol Integration Pending)";
}

const char* OpenVPNClient::getStatus() const {
    if (is_connected) {
        return "connected";
    }
    return "disconnected";
}

uint64_t OpenVPNClient::getBytesIn() const {
    return bytes_in;
}

uint64_t OpenVPNClient::getBytesOut() const {
    return bytes_out;
}

void OpenVPNClient::setStatusCallback(StatusCallback callback) {
    status_callback = callback;
}
