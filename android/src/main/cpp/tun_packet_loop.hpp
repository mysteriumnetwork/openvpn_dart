#ifndef TUN_PACKET_LOOP_HPP
#define TUN_PACKET_LOOP_HPP

#include <cstdint>
#include <cstring>
#include <unistd.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <errno.h>
#include <android/log.h>
#include <functional>

#define LOG_TAG "TunPacketLoop"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

class TunPacketLoop {
public:
    static constexpr int MAX_PACKET_SIZE = 65536;
    static constexpr int SELECT_TIMEOUT_MS = 100;
    
    // Callback for packet processing
    using PacketCallback = std::function<void(const uint8_t*, size_t, bool)>; // data, len, is_from_tun
    
    struct Stats {
        uint64_t packets_in = 0;
        uint64_t packets_out = 0;
        uint64_t bytes_in = 0;
        uint64_t bytes_out = 0;
        uint64_t errors = 0;
    };
    
    TunPacketLoop(int tun_fd, int udp_fd)
        : tun_fd_(tun_fd), udp_fd_(udp_fd), running_(false) {
    }
    
    void setPacketCallback(PacketCallback cb) {
        packet_callback_ = cb;
    }
    
    virtual ~TunPacketLoop() = default;
    
    // Process a single cycle
    void processCycle() {
        if (tun_fd_ < 0 || udp_fd_ < 0) {
            return;
        }
        
        // Use select to check for available data
        fd_set readfds;
        FD_ZERO(&readfds);
        FD_SET(tun_fd_, &readfds);
        FD_SET(udp_fd_, &readfds);
        
        struct timeval tv;
        tv.tv_sec = 0;
        tv.tv_usec = SELECT_TIMEOUT_MS * 1000;
        
        int maxfd = (tun_fd_ > udp_fd_) ? tun_fd_ : udp_fd_;
        int ret = select(maxfd + 1, &readfds, nullptr, nullptr, &tv);
        
        if (ret < 0) {
            stats_.errors++;
            return;
        }
        
        if (ret == 0) {
            // Timeout - no data available
            return;
        }
        
        // Check TUN device for outgoing packets
        if (FD_ISSET(tun_fd_, &readfds)) {
            readFromTun();
        }
        
        // Check UDP socket for incoming packets
        if (FD_ISSET(udp_fd_, &readfds)) {
            readFromUdp();
        }
    }
    
    const Stats& getStats() const {
        return stats_;
    }
    
protected:
    // Override these in subclass to handle actual encryption
    virtual uint8_t* encryptPacket(const uint8_t* plaintext, size_t& length) {
        // Default: no encryption, just return plaintext
        return const_cast<uint8_t*>(plaintext);
    }
    
    virtual uint8_t* decryptPacket(const uint8_t* ciphertext, size_t& length) {
        // Default: no decryption, just return ciphertext
        return const_cast<uint8_t*>(ciphertext);
    }
    
private:
    void readFromTun() {
        uint8_t buffer[MAX_PACKET_SIZE];
        ssize_t nread = read(tun_fd_, buffer, MAX_PACKET_SIZE);
        
        if (nread < 0) {
            if (errno != EAGAIN && errno != EWOULDBLOCK) {
                LOGE("TUN read error: %s", strerror(errno));
                stats_.errors++;
            }
            return;
        }
        
        if (nread == 0) {
            return;
        }
        
        stats_.packets_out++;
        stats_.bytes_out += nread;
        
        LOGD("TUN packet out: %zd bytes", nread);
        
        // Callback for encryption and sending
        if (packet_callback_) {
            packet_callback_(buffer, nread, true);
        }
    }
    
    void readFromUdp() {
        uint8_t buffer[MAX_PACKET_SIZE];
        struct sockaddr_in addr;
        socklen_t addr_len = sizeof(addr);
        
        ssize_t nread = recvfrom(udp_fd_, buffer, MAX_PACKET_SIZE, 0,
                                 (struct sockaddr*)&addr, &addr_len);
        
        if (nread < 0) {
            // EAGAIN/EWOULDBLOCK is normal for non-blocking socket
            if (errno != EAGAIN && errno != EWOULDBLOCK) {
                LOGE("UDP read error: %s", strerror(errno));
                stats_.errors++;
            }
            return;
        }
        
        if (nread == 0) {
            return;
        }
        
        stats_.packets_in++;
        stats_.bytes_in += nread;
        
        LOGD("UDP packet in: %zd bytes", nread);
        
        // Callback for decryption and TUN write
        if (packet_callback_) {
            packet_callback_(buffer, nread, false);
        }
    }
    
    int tun_fd_;
    int udp_fd_;
    bool running_;
    Stats stats_;
    PacketCallback packet_callback_;
};

#endif // TUN_PACKET_LOOP_HPP
