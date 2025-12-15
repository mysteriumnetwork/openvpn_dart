#ifndef OPENVPN_PROTOCOL_HPP
#define OPENVPN_PROTOCOL_HPP

#include <string>
#include <vector>
#include <cstdint>
#include <memory>

// Forward declarations
namespace OpenVPNTLS {
    class TLSContext;
}

// OpenVPN Protocol Constants
namespace OpenVPNProtocol {

// Opcodes
constexpr uint8_t P_CONTROL_HARD_RESET_CLIENT_V1 = 1;
constexpr uint8_t P_CONTROL_HARD_RESET_SERVER_V1 = 2;
constexpr uint8_t P_CONTROL_SOFT_RESET_V1 = 3;
constexpr uint8_t P_CONTROL_V1 = 4;
constexpr uint8_t P_ACK_V1 = 5;
constexpr uint8_t P_DATA_V1 = 6;
constexpr uint8_t P_DATA_V2 = 9;

constexpr uint8_t P_CONTROL_HARD_RESET_CLIENT_V2 = 7;
constexpr uint8_t P_CONTROL_HARD_RESET_SERVER_V2 = 8;

constexpr uint8_t P_CONTROL_HARD_RESET_CLIENT_V3 = 10;
constexpr uint8_t P_CONTROL_WKC_V1 = 11;

// Key methods
constexpr uint8_t KEY_METHOD_2 = 2;

// Packet structure helpers
struct PacketHeader {
    uint8_t opcode;
    uint32_t session_id;
    uint8_t message_packet_id[3]; // 24-bit packet ID
    uint32_t timestamp;
    uint8_t array_len;
    
    std::vector<uint8_t> serialize() const;
    static PacketHeader deserialize(const uint8_t* data, size_t len);
};

// OpenVPN Control Packet
class ControlPacket {
public:
    uint8_t opcode;
    uint32_t session_id;
    uint32_t packet_id;
    std::vector<uint8_t> payload;
    
    ControlPacket(uint8_t op = 0) : opcode(op), session_id(0), packet_id(0) {}
    
    std::vector<uint8_t> serialize() const;
    static std::unique_ptr<ControlPacket> deserialize(const uint8_t* data, size_t len);
};

// Simple OpenVPN handshake manager
class HandshakeManager {
public:
    HandshakeManager();
    ~HandshakeManager();
    
    // Initialize handshake with config
    bool init(const std::string& config_content,
              const std::string& username,
              const std::string& password);
    
    // Get next packet to send to server
    std::vector<uint8_t> getNextPacket();
    
    // Process packet from server
    bool processPacket(const uint8_t* data, size_t len);
    
    // Check if handshake is complete
    bool isComplete() const { return handshake_complete_; }
    
    // Check if we have data to send
    bool hasPendingData() const { return !pending_packets_.empty(); }
    
    // Get current state
    enum State {
        INIT,
        SEND_RESET,
        WAIT_RESET_ACK,
        TLS_HANDSHAKE,
        SEND_AUTH,
        WAIT_PUSH_REPLY,
        CONNECTED,
        ERROR
    };
    
    State getState() const { return state_; }
    const std::string& getError() const { return error_msg_; }
    
private:
    State state_;
    bool handshake_complete_;
    uint32_t local_session_id_;
    uint32_t remote_session_id_;
    uint32_t packet_id_;
    std::string config_content_;
    std::string username_;
    std::string password_;
    std::vector<std::vector<uint8_t>> pending_packets_;
    std::string error_msg_;
    std::unique_ptr<OpenVPNTLS::TLSContext> tls_;
    
    void createResetPacket();
    void createAuthPacket();
    void processPushReply(const std::string& reply);
    bool initializeTLS();
    bool extractCertificates(std::string& ca, std::string& cert, std::string& key);
};

} // namespace OpenVPNProtocol

#endif // OPENVPN_PROTOCOL_HPP
