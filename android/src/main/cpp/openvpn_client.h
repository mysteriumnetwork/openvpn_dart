#ifndef OPENVPN_CLIENT_H
#define OPENVPN_CLIENT_H

#include <string>
#include <cstdint>
#include <functional>

typedef std::function<void(const char*)> StatusCallback;

// Forward declaration
class OpenVPN3Client;

class OpenVPNClient {
public:
    static OpenVPNClient* getInstance();

    bool initialize();
    bool connect(const std::string& config_path,
                 const std::string& username,
                 const std::string& password);
    bool disconnect();
    
    void setTunFd(int fd);

    const char* getVersion() const;
    const char* getStatus() const;
    uint64_t getBytesIn() const;
    uint64_t getBytesOut() const;

    void setStatusCallback(StatusCallback callback);

private:
    OpenVPNClient();
    ~OpenVPNClient();

    void connectionThread();
    std::string readConfigFile(const std::string& path);

    bool is_connected;
    uint64_t bytes_in;
    uint64_t bytes_out;
    std::string config_path_;
    std::string username_;
    std::string password_;
    int tun_fd_;
    StatusCallback status_callback;
    OpenVPN3Client* ovpn_client;
};

#endif // OPENVPN_CLIENT_H
