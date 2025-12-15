#ifndef OPENVPN_TLS_WRAPPER_HPP
#define OPENVPN_TLS_WRAPPER_HPP

#include <string>
#include <vector>
#include <memory>

#ifdef HAVE_OPENSSL
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/bio.h>
#endif

namespace OpenVPNTLS {

class TLSContext {
public:
    TLSContext();
    ~TLSContext();
    
    // Initialize TLS with certificates from config
    bool init(const std::string& ca_cert,
              const std::string& client_cert,
              const std::string& client_key);
    
    // Perform TLS handshake
    // Returns: -1 on error, 0 if needs more data, 1 if complete
    int doHandshake();
    
    // Check if handshake is complete
    bool isHandshakeComplete() const { return handshake_complete_; }
    
    // Get TLS packet to send to server
    std::vector<uint8_t> getTLSPacketToSend();
    
    // Process TLS packet from server
    bool processTLSPacket(const uint8_t* data, size_t len);
    
    // Encrypt data for sending through TLS tunnel
    std::vector<uint8_t> encrypt(const uint8_t* data, size_t len);
    
    // Decrypt data from TLS tunnel
    std::vector<uint8_t> decrypt(const uint8_t* data, size_t len);
    
    // Get error message
    std::string getError() const { return error_msg_; }
    
private:
#ifdef HAVE_OPENSSL
    SSL_CTX* ssl_ctx_;
    SSL* ssl_;
    BIO* bio_in_;   // BIO for input (data from server)
    BIO* bio_out_;  // BIO for output (data to send to server)
#else
    void* ssl_ctx_;
    void* ssl_;
    void* bio_in_;
    void* bio_out_;
#endif
    bool handshake_complete_;
    std::string error_msg_;
    
    // Helper to load certificate from PEM string
    bool loadCertificateFromString(const std::string& pem_data, int type);
    
    void setError(const std::string& msg);
};

} // namespace OpenVPNTLS

#endif // OPENVPN_TLS_WRAPPER_HPP
