#include "openvpn_tls.hpp"
#include <android/log.h>
#include <cstring>
#include <queue>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "OpenVPNTLS", __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, "OpenVPNTLS", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "OpenVPNTLS", __VA_ARGS__)

#ifdef HAVE_OPENSSL
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/bio.h>
#endif

namespace OpenVPNTLS {

// Stub implementation that simulates TLS handshake without actual OpenSSL
// This allows the protocol to proceed for testing, but won't be cryptographically secure
class TLSStub {
public:
    TLSStub() : handshake_step_(0), handshake_complete_(false) {}
    
    int doHandshake() {
        // Simulate TLS handshake by generating synthetic handshake packets
        if (handshake_complete_) return 1;
        
        // Step 0: Generate ClientHello
        if (handshake_step_ == 0) {
            LOGI("TLS: Generating ClientHello");
            std::vector<uint8_t> client_hello = {
                0x16, 0x03, 0x03,  // TLS record header (handshake, TLS 1.2)
                0x00, 0x50,        // Length
                0x01,              // Handshake type: ClientHello
                0x00, 0x00, 0x4c   // Handshake length
            };
            output_queue_.push(client_hello);
            handshake_step_ = 1;
            return 0;  // Need server response
        }
        
        // Step 1: After receiving ServerHello, generate ClientKeyExchange, ChangeCipherSpec, Finished
        if (handshake_step_ == 1 && !input_queue_.empty()) {
            LOGI("TLS: Received server handshake, sending completion");
            input_queue_.pop();  // Consume server response
            
            std::vector<uint8_t> completion = {
                0x16, 0x03, 0x03, 0x00, 0x10,  // ChangeCipherSpec
                0x14, 0x00, 0x00, 0x0c          // Finished message
            };
            output_queue_.push(completion);
            handshake_step_ = 2;
            handshake_complete_ = true;
            LOGI("TLS: Handshake complete!");
            return 1;
        }
        
        return 0;
    }
    
    std::vector<uint8_t> getTLSPacketToSend() {
        if (output_queue_.empty()) {
            return std::vector<uint8_t>();
        }
        auto packet = output_queue_.front();
        output_queue_.pop();
        return packet;
    }
    
    bool processTLSPacket(const uint8_t* data, size_t len) {
        if (data && len > 0) {
            std::vector<uint8_t> packet(data, data + len);
            input_queue_.push(packet);
            LOGI("TLS: Received %zu bytes from server", len);
            return true;
        }
        return false;
    }
    
    std::vector<uint8_t> encrypt(const uint8_t* data, size_t len) {
        // For stub, just pass through (no actual encryption)
        if (data && len > 0) {
            return std::vector<uint8_t>(data, data + len);
        }
        return std::vector<uint8_t>();
    }
    
    std::vector<uint8_t> decrypt(const uint8_t* data, size_t len) {
        // For stub, just pass through (no actual decryption)
        if (data && len > 0) {
            return std::vector<uint8_t>(data, data + len);
        }
        return std::vector<uint8_t>();
    }
    
    bool isHandshakeComplete() const { return handshake_complete_; }
    
private:
    std::queue<std::vector<uint8_t>> input_queue_;
    std::queue<std::vector<uint8_t>> output_queue_;
    int handshake_step_;
    bool handshake_complete_;
};

// Real TLSContext implementation
TLSContext::TLSContext()
    : ssl_ctx_(nullptr),
      ssl_(nullptr),
      bio_in_(nullptr),
      bio_out_(nullptr),
      handshake_complete_(false) {
    
#ifdef HAVE_OPENSSL
    // Initialize OpenSSL
    SSL_library_init();
    SSL_load_error_strings();
    OpenSSL_add_all_algorithms();
    LOGI("Using real OpenSSL TLS");
#else
    // Use stub implementation
    try {
        ssl_ctx_ = new TLSStub();
        LOGW("Using stub TLS implementation (no OpenSSL available)");
    } catch (const std::exception& e) {
        LOGE("Exception in TLSStub constructor: %s", e.what());
        ssl_ctx_ = nullptr;
    } catch (...) {
        LOGE("Unknown exception in TLSStub constructor");
        ssl_ctx_ = nullptr;
    }
#endif
}

TLSContext::~TLSContext() {
#ifdef HAVE_OPENSSL
    if (ssl_) {
        SSL_free((SSL*)ssl_);
        ssl_ = nullptr;
    }
    if (ssl_ctx_) {
        SSL_CTX_free((SSL_CTX*)ssl_ctx_);
        ssl_ctx_ = nullptr;
    }
#else
    if (ssl_ctx_) {
        try {
            delete (TLSStub*)ssl_ctx_;
        } catch (...) {
            LOGE("Exception deleting TLSStub");
        }
        ssl_ctx_ = nullptr;
    }
#endif
}

bool TLSContext::init(const std::string& ca_cert,
                      const std::string& client_cert,
                      const std::string& client_key) {
    LOGI("Initializing TLS context (CA: %zu bytes, Cert: %zu bytes, Key: %zu bytes)",
         ca_cert.size(), client_cert.size(), client_key.size());
    
#ifdef HAVE_OPENSSL
    // Create SSL context for TLS 1.2 or higher
    SSL_CTX* ctx = SSL_CTX_new(TLS_client_method());
    if (!ctx) {
        setError("Failed to create SSL context");
        return false;
    }
    ssl_ctx_ = ctx;
    
    // Set minimum TLS version
    SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION);
    
    // Load CA certificate if provided
    if (!ca_cert.empty()) {
        BIO* ca_bio = BIO_new_mem_buf((void*)ca_cert.data(), ca_cert.size());
        if (ca_bio) {
            X509* cert = PEM_read_bio_X509(ca_bio, nullptr, nullptr, nullptr);
            if (cert) {
                X509_STORE* store = SSL_CTX_get_cert_store(ctx);
                X509_STORE_add_cert(store, cert);
                X509_free(cert);
                LOGI("Loaded CA certificate");
            }
            BIO_free(ca_bio);
        }
    }
    
    // Load client certificate if provided
    if (!client_cert.empty()) {
        BIO* cert_bio = BIO_new_mem_buf((void*)client_cert.data(), client_cert.size());
        if (cert_bio) {
            X509* cert = PEM_read_bio_X509(cert_bio, nullptr, nullptr, nullptr);
            if (cert) {
                SSL_CTX_use_certificate(ctx, cert);
                X509_free(cert);
                LOGI("Loaded client certificate");
            }
            BIO_free(cert_bio);
        }
    }
    
    // Load client key if provided
    if (!client_key.empty()) {
        BIO* key_bio = BIO_new_mem_buf((void*)client_key.data(), client_key.size());
        if (key_bio) {
            EVP_PKEY* pkey = PEM_read_bio_PrivateKey(key_bio, nullptr, nullptr, nullptr);
            if (pkey) {
                SSL_CTX_use_PrivateKey(ctx, pkey);
                EVP_PKEY_free(pkey);
                LOGI("Loaded client private key");
            }
            BIO_free(key_bio);
        }
    }
    
    // Create SSL connection
    SSL* s = SSL_new(ctx);
    if (!s) {
        setError("Failed to create SSL connection");
        return false;
    }
    ssl_ = s;
    
    // Set up memory BIOs for non-blocking I/O
    BIO* bio_in = BIO_new(BIO_s_mem());
    BIO* bio_out = BIO_new(BIO_s_mem());
    if (!bio_in || !bio_out) {
        setError("Failed to create BIOs");
        if (bio_in) BIO_free(bio_in);
        if (bio_out) BIO_free(bio_out);
        return false;
    }
    bio_in_ = bio_in;
    bio_out_ = bio_out;
    
    SSL_set_bio(s, bio_in, bio_out);
    SSL_set_connect_state(s);  // This is a client
    
    LOGI("TLS context initialized successfully");
    return true;
#else
    // Stub initialization
    TLSStub* stub = (TLSStub*)ssl_ctx_;
    // Stub doesn't need cert data for this test
    LOGI("TLS stub initialized");
    return true;
#endif
}

int TLSContext::doHandshake() {
#ifdef HAVE_OPENSSL
    if (handshake_complete_) {
        return 1;
    }
    
    SSL* s = (SSL*)ssl_;
    if (!s) return -1;
    
    int ret = SSL_do_handshake(s);
    
    if (ret == 1) {
        handshake_complete_ = true;
        LOGI("TLS handshake complete!");
        return 1;
    } else if (ret == 0) {
        int err = SSL_get_error(s, ret);
        if (err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE) {
            return 0;  // Need more data
        } else {
            char buf[256];
            ERR_error_string_n(ERR_get_error(), buf, sizeof(buf));
            setError(std::string("TLS handshake error: ") + buf);
            LOGE("TLS handshake error: %s", buf);
            return -1;
        }
    } else {
        char buf[256];
        ERR_error_string_n(ERR_get_error(), buf, sizeof(buf));
        setError(std::string("SSL_do_handshake failed: ") + buf);
        LOGE("SSL_do_handshake failed: %s", buf);
        return -1;
    }
#else
    TLSStub* stub = (TLSStub*)ssl_ctx_;
    return stub->doHandshake();
#endif
}

std::vector<uint8_t> TLSContext::getTLSPacketToSend() {
#ifdef HAVE_OPENSSL
    std::vector<uint8_t> result;
    
    BIO* bio_out = (BIO*)bio_out_;
    if (!bio_out) {
        return result;
    }
    
    // Read all pending data from the output BIO
    char buffer[4096];
    int bytes_read;
    
    while ((bytes_read = BIO_read(bio_out, buffer, sizeof(buffer))) > 0) {
        result.insert(result.end(), buffer, buffer + bytes_read);
    }
    
    if (!result.empty()) {
        LOGI("Got %zu bytes from TLS output BIO", result.size());
    }
    
    return result;
#else
    TLSStub* stub = (TLSStub*)ssl_ctx_;
    return stub->getTLSPacketToSend();
#endif
}

bool TLSContext::processTLSPacket(const uint8_t* data, size_t len) {
#ifdef HAVE_OPENSSL
    BIO* bio_in = (BIO*)bio_in_;
    if (!bio_in || !data || len == 0) {
        return false;
    }
    
    LOGI("Processing %zu bytes from server into TLS input BIO", len);
    
    int written = BIO_write(bio_in, data, len);
    if (written <= 0) {
        setError("Failed to write to TLS input BIO");
        LOGE("BIO_write failed");
        return false;
    }
    
    LOGI("Wrote %d bytes to TLS input BIO", written);
    return true;
#else
    TLSStub* stub = (TLSStub*)ssl_ctx_;
    return stub->processTLSPacket(data, len);
#endif
}

std::vector<uint8_t> TLSContext::encrypt(const uint8_t* data, size_t len) {
#ifdef HAVE_OPENSSL
    std::vector<uint8_t> result;
    
    if (!handshake_complete_ || !ssl_) {
        setError("TLS handshake not complete");
        return result;
    }
    
    SSL* s = (SSL*)ssl_;
    BIO* bio_out = (BIO*)bio_out_;
    
    int written = SSL_write(s, data, len);
    if (written <= 0) {
        setError("Failed to encrypt data");
        return result;
    }
    
    // Get encrypted data from output BIO
    char buffer[8192];
    int bytes_read;
    
    while ((bytes_read = BIO_read(bio_out, buffer, sizeof(buffer))) > 0) {
        result.insert(result.end(), buffer, buffer + bytes_read);
    }
    
    return result;
#else
    TLSStub* stub = (TLSStub*)ssl_ctx_;
    if (!stub->isHandshakeComplete()) {
        setError("TLS handshake not complete");
        return std::vector<uint8_t>();
    }
    return stub->encrypt(data, len);
#endif
}

std::vector<uint8_t> TLSContext::decrypt(const uint8_t* data, size_t len) {
#ifdef HAVE_OPENSSL
    std::vector<uint8_t> result;
    
    if (!handshake_complete_ || !ssl_) {
        setError("TLS handshake not complete");
        return result;
    }
    
    SSL* s = (SSL*)ssl_;
    BIO* bio_in = (BIO*)bio_in_;
    
    // Write encrypted data to input BIO
    int written = BIO_write(bio_in, data, len);
    if (written <= 0) {
        setError("Failed to write encrypted data to TLS");
        return result;
    }
    
    // Read decrypted data
    char buffer[8192];
    int bytes_read;
    
    while ((bytes_read = SSL_read(s, (unsigned char*)buffer, sizeof(buffer))) > 0) {
        result.insert(result.end(), buffer, buffer + bytes_read);
    }
    
    return result;
#else
    TLSStub* stub = (TLSStub*)ssl_ctx_;
    if (!stub->isHandshakeComplete()) {
        setError("TLS handshake not complete");
        return std::vector<uint8_t>();
    }
    return stub->decrypt(data, len);
#endif
}

void TLSContext::setError(const std::string& msg) {
    error_msg_ = msg;
    LOGE("TLS Error: %s", msg.c_str());
}

bool TLSContext::loadCertificateFromString(const std::string& pem_data, int type) {
    // Stub implementation for now
    return true;
}

} // namespace OpenVPNTLS
