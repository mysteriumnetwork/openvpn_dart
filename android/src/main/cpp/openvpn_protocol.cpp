#include "openvpn_protocol.hpp"
#include "openvpn_tls.hpp"
#include <android/log.h>
#include <cstring>
#include <random>
#include <chrono>
#include <regex>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "OpenVPNProtocol", __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, "OpenVPNProtocol", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "OpenVPNProtocol", __VA_ARGS__)

namespace OpenVPNProtocol {

// PacketHeader implementation
std::vector<uint8_t> PacketHeader::serialize() const {
    std::vector<uint8_t> result;
    result.reserve(16);
    
    // Opcode and key ID
    result.push_back(opcode << 3);
    
    // Session ID (8 bytes)
    for (int i = 7; i >= 0; i--) {
        result.push_back((session_id >> (i * 8)) & 0xFF);
    }
    
    return result;
}

// ControlPacket implementation
std::vector<uint8_t> ControlPacket::serialize() const {
    std::vector<uint8_t> result;
    
    // Opcode (high 5 bits) + Key ID (low 3 bits)
    result.push_back((opcode << 3) | 0x00);
    
    // Session ID (8 bytes) - network byte order (big-endian)
    // Pad upper 32 bits with zeros since session_id is uint32_t
    result.push_back(0x00);
    result.push_back(0x00);
    result.push_back(0x00);
    result.push_back(0x00);
    // Lower 32 bits contain actual session_id
    result.push_back((session_id >> 24) & 0xFF);
    result.push_back((session_id >> 16) & 0xFF);
    result.push_back((session_id >> 8) & 0xFF);
    result.push_back((session_id >> 0) & 0xFF);
    
    // Packet ID array length (1 byte) - for RESET it's typically 0
    if (opcode == P_CONTROL_HARD_RESET_CLIENT_V2 || opcode == P_CONTROL_HARD_RESET_CLIENT_V3) {
        // RESET packets don't have packet IDs in the array
        result.push_back(0x00);
    } else {
        // Other control packets have packet ID array
        result.push_back(0x01);
        
        // Packet ID (4 bytes) - network byte order  
        result.push_back((packet_id >> 24) & 0xFF);
        result.push_back((packet_id >> 16) & 0xFF);
        result.push_back((packet_id >> 8) & 0xFF);
        result.push_back((packet_id >> 0) & 0xFF);
    }
    
    // Payload
    result.insert(result.end(), payload.begin(), payload.end());
    
    return result;
}

std::unique_ptr<ControlPacket> ControlPacket::deserialize(const uint8_t* data, size_t len) {
    if (len < 10) {
        return nullptr;
    }
    
    auto packet = std::make_unique<ControlPacket>();
    
    // Extract opcode from first byte (high 5 bits)
    packet->opcode = data[0] >> 3;
    
    // Extract session ID (8 bytes)
    packet->session_id = 0;
    for (int i = 0; i < 8; i++) {
        packet->session_id = (packet->session_id << 8) | data[1 + i];
    }
    
    // Extract array length
    size_t offset = 9;
    if (offset >= len) return packet;
    
    uint8_t array_len = data[offset++];
    
    // Skip packet IDs (4 bytes each)
    offset += array_len * 4;
    
    // Copy payload
    if (offset < len) {
        packet->payload.assign(data + offset, data + len);
    }
    
    return packet;
}

// HandshakeManager implementation
HandshakeManager::HandshakeManager()
    : state_(INIT),
      handshake_complete_(false),
      local_session_id_(0),
      remote_session_id_(0),
      packet_id_(1) {
}

HandshakeManager::~HandshakeManager() {
}

bool HandshakeManager::init(const std::string& config_content,
                            const std::string& username,
                            const std::string& password) {
    config_content_ = config_content;
    username_ = username;
    password_ = password;
    
    // Generate random local session ID (64-bit, but use lower 32 bits for OpenVPN)
    std::random_device rd;
    std::mt19937_64 gen(rd());
    std::uniform_int_distribution<uint64_t> dis;
    uint64_t session = dis(gen);
    local_session_id_ = static_cast<uint32_t>(session & 0xFFFFFFFFLL);
    
    LOGI("Handshake initialized with session ID: 0x%08X", local_session_id_);
    
    // Initialize TLS first
    if (!initializeTLS()) {
        LOGE("Failed to initialize TLS");
        state_ = ERROR;
        return false;
    }
    
    // Create initial RESET packet
    createResetPacket();
    state_ = SEND_RESET;
    
    return true;
}

bool HandshakeManager::initializeTLS() {
    LOGI("Initializing TLS");
    
    try {
        std::string ca_cert, client_cert, client_key;
        
        if (!extractCertificates(ca_cert, client_cert, client_key)) {
            LOGE("Failed to extract certificates from config");
            error_msg_ = "No certificates found in config";
            return false;
        }
        
        tls_ = std::make_unique<OpenVPNTLS::TLSContext>();
        
        if (!tls_->init(ca_cert, client_cert, client_key)) {
            LOGE("TLS initialization failed: %s", tls_->getError().c_str());
            error_msg_ = "TLS init failed: " + tls_->getError();
            return false;
        }
        
        LOGI("TLS initialized successfully");
        return true;
    } catch (const std::exception& e) {
        LOGE("Exception during TLS initialization: %s", e.what());
        error_msg_ = "Exception: " + std::string(e.what());
        return false;
    } catch (...) {
        LOGE("Unknown exception during TLS initialization");
        error_msg_ = "Unknown exception during TLS init";
        return false;
    }
}

bool HandshakeManager::extractCertificates(std::string& ca, std::string& cert, std::string& key) {
    // Extract CA certificate
    std::regex ca_regex(R"(<ca>([\s\S]*?)</ca>)");
    std::smatch match;
    
    if (std::regex_search(config_content_, match, ca_regex)) {
        ca = match[1];
        LOGI("Extracted CA certificate (%zu bytes)", ca.size());
    } else {
        LOGW("No CA certificate found in config");
    }
    
    // Extract client certificate
    std::regex cert_regex(R"(<cert>([\s\S]*?)</cert>)");
    if (std::regex_search(config_content_, match, cert_regex)) {
        cert = match[1];
        LOGI("Extracted client certificate (%zu bytes)", cert.size());
    }
    
    // Extract client key
    std::regex key_regex(R"(<key>([\s\S]*?)</key>)");
    if (std::regex_search(config_content_, match, key_regex)) {
        key = match[1];
        LOGI("Extracted client key (%zu bytes)", key.size());
    }
    
    return !ca.empty();
}

void HandshakeManager::createResetPacket() {
    ControlPacket packet(P_CONTROL_HARD_RESET_CLIENT_V2);
    // For initial RESET, session_id should be random but packet array should be 0
    packet.session_id = local_session_id_;
    packet.packet_id = 0;  // First packet is always 0
    
    // RESET packet needs empty payload
    packet.payload.clear();
    
    auto serialized = packet.serialize();
    pending_packets_.push_back(serialized);
    
    LOGI("Created RESET packet: opcode=%d, session=0x%016lX, packet_id=%u, size=%zu",
         packet.opcode, packet.session_id, packet.packet_id, serialized.size());
    
    // Log packet bytes for debugging
    std::string hex;
    for (size_t i = 0; i < std::min(serialized.size(), size_t(32)); i++) {
        char buf[4];
        snprintf(buf, sizeof(buf), "%02x ", serialized[i]);
        hex += buf;
    }
    LOGI("RESET packet bytes: %s", hex.c_str());
    
    // Immediately initiate TLS handshake and send ClientHello
    // Modern OpenVPN doesn't wait for SERVER_RESET before starting TLS
    if (tls_) {
        state_ = TLS_HANDSHAKE;
        int tls_ret = tls_->doHandshake();
        LOGI("Initiating TLS handshake after RESET, doHandshake() returned: %d", tls_ret);
        auto tls_packet = tls_->getTLSPacketToSend();
        if (!tls_packet.empty()) {
            LOGI("Sending TLS ClientHello (%zu bytes) with RESET", tls_packet.size());
            ControlPacket ctrl(P_CONTROL_V1);
            ctrl.session_id = local_session_id_;
            ctrl.packet_id = packet_id_++;
            ctrl.payload.assign(tls_packet.begin(), tls_packet.end());
            pending_packets_.push_back(ctrl.serialize());
        }
    }
}

void HandshakeManager::createAuthPacket() {
    ControlPacket packet(P_CONTROL_V1);
    packet.session_id = local_session_id_;
    packet.packet_id = packet_id_++;
    
    // Build auth payload
    std::string push_request = "PUSH_REQUEST\n";
    
    // If TLS is available, encrypt the auth message
    if (tls_) {
        auto encrypted = tls_->encrypt(reinterpret_cast<const uint8_t*>(push_request.data()), push_request.size());
        packet.payload.assign(encrypted.begin(), encrypted.end());
        LOGI("Created AUTH/PUSH_REQUEST packet (TLS encrypted): size=%zu", packet.payload.size());
    } else {
        packet.payload.assign(push_request.begin(), push_request.end());
        LOGI("Created AUTH/PUSH_REQUEST packet (unencrypted): size=%zu", packet.payload.size());
    }
    
    auto serialized = packet.serialize();
    pending_packets_.push_back(serialized);
}

std::vector<uint8_t> HandshakeManager::getNextPacket() {
    if (pending_packets_.empty()) {
        return std::vector<uint8_t>();
    }
    
    auto packet = pending_packets_.front();
    pending_packets_.erase(pending_packets_.begin());
    return packet;
}

bool HandshakeManager::processPacket(const uint8_t* data, size_t len) {
    // First, always try to deserialize as a control packet
    auto packet = ControlPacket::deserialize(data, len);
    if (!packet) {
        LOGE("Failed to deserialize packet");
        return false;
    }
    
    LOGI("Received packet: opcode=%d, session=0x%016lX, payload_size=%zu",
         packet->opcode, packet->session_id, packet->payload.size());
    
    // Handle based on current state and opcode
    switch (packet->opcode) {
        case P_CONTROL_HARD_RESET_SERVER_V2: {
            LOGI("Received SERVER RESET");
            remote_session_id_ = packet->session_id;
            
            // Send ACK
            ControlPacket ack(P_ACK_V1);
            ack.session_id = local_session_id_;
            ack.packet_id = packet_id_++;
            pending_packets_.push_back(ack.serialize());
            
            // Move to TLS handshake and send TLS ClientHello
            state_ = TLS_HANDSHAKE;
            if (tls_) {
                int tls_ret = tls_->doHandshake();
                LOGI("Initiating TLS handshake, doHandshake() returned: %d", tls_ret);
                auto tls_packet = tls_->getTLSPacketToSend();
                if (!tls_packet.empty()) {
                    LOGI("Sending TLS ClientHello (%zu bytes)", tls_packet.size());
                    ControlPacket ctrl(P_CONTROL_V1);
                    ctrl.session_id = local_session_id_;
                    ctrl.packet_id = packet_id_++;
                    ctrl.payload.assign(tls_packet.begin(), tls_packet.end());
                    pending_packets_.push_back(ctrl.serialize());
                }
            }
            break;
        }
            
        case P_CONTROL_V1: {
            LOGI("Received CONTROL packet with %zu bytes payload", packet->payload.size());
            
            // During TLS handshake, payload contains TLS records
            if (state_ == TLS_HANDSHAKE && tls_ && !packet->payload.empty()) {
                LOGI("Processing TLS data from control packet");
                
                // Feed TLS payload to OpenSSL
                tls_->processTLSPacket(packet->payload.data(), packet->payload.size());
                
                // Continue TLS handshake
                int tls_ret = tls_->doHandshake();
                LOGI("TLS doHandshake() returned: %d", tls_ret);
                
                if (tls_ret == 1) {
                    // TLS handshake complete!
                    LOGI("TLS handshake complete!");
                    state_ = SEND_AUTH;
                    // Send PUSH_REQUEST wrapped in TLS
                    createAuthPacket();
                } else if (tls_ret < 0) {
                    LOGE("TLS handshake error!");
                    // Don't fail completely, might recover
                }
                
                // Get any TLS data to send back
                auto tls_packet = tls_->getTLSPacketToSend();
                if (!tls_packet.empty()) {
                    LOGI("Sending TLS response (%zu bytes)", tls_packet.size());
                    ControlPacket ctrl(P_CONTROL_V1);
                    ctrl.session_id = local_session_id_;
                    ctrl.packet_id = packet_id_++;
                    ctrl.payload.assign(tls_packet.begin(), tls_packet.end());
                    pending_packets_.push_back(ctrl.serialize());
                }
            }
            // After TLS handshake, check for PUSH_REPLY
            else if (state_ >= SEND_AUTH && packet->payload.size() > 0) {
                std::string payload_str(packet->payload.begin(), packet->payload.end());
                LOGI("Control payload: %s", payload_str.c_str());
                
                if (payload_str.find("PUSH_REPLY") != std::string::npos) {
                    processPushReply(payload_str);
                    handshake_complete_ = true;
                    state_ = CONNECTED;
                    LOGI("Handshake complete!");
                    return true;
                }
            }
            
            // Send ACK
            {
                ControlPacket ack(P_ACK_V1);
                ack.session_id = local_session_id_;
                ack.packet_id = packet_id_++;
                pending_packets_.push_back(ack.serialize());
            }
            break;
        }
            
        case P_ACK_V1:
            LOGI("Received ACK");
            // ACK processed, continue
            break;
            
        default:
            LOGW("Unhandled opcode: %d", packet->opcode);
            break;
    }
    
    return false;
}

void HandshakeManager::processPushReply(const std::string& reply) {
    LOGI("Processing PUSH_REPLY: %s", reply.c_str());
    
    // Parse pushed options (ifconfig, route, dhcp-option, etc.)
    // For now, just log it
    // TODO: Apply network configuration
}

} // namespace OpenVPNProtocol
