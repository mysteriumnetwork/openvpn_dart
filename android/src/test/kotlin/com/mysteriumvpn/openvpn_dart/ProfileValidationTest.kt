package com.mysteriumvpn.openvpn_dart

import de.blinkt.openvpn.VpnProfile
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class ProfileValidationTest {

    private fun profile(authType: Int, alias: String? = null) = VpnProfile("test").apply {
        mAuthenticationType = authType
        mAlias = alias
    }

    /** The reason the guard has to exist: a config with no client-auth directive keeps this default. */
    @Test
    fun a_fresh_profile_defaults_to_keystore_auth_with_no_alias() {
        val fresh = VpnProfile("test")
        assertEquals(VpnProfile.TYPE_KEYSTORE, fresh.mAuthenticationType)
        assertNull(fresh.mAlias)
    }

    @Test
    fun flags_keystore_auth_without_an_alias() {
        listOf(
            VpnProfile.TYPE_KEYSTORE,
            VpnProfile.TYPE_USERPASS_KEYSTORE,
            VpnProfile.TYPE_EXTERNAL_APP,
        ).forEach { assertTrue(OpenVPNBackend.needsKeystoreCertificate(profile(it)), "auth type $it") }
    }

    @Test
    fun does_not_flag_auth_types_that_need_no_keystore_cert() {
        listOf(
            VpnProfile.TYPE_CERTIFICATES,
            VpnProfile.TYPE_PKCS12,
            VpnProfile.TYPE_USERPASS,
            VpnProfile.TYPE_STATICKEYS,
            VpnProfile.TYPE_USERPASS_CERTIFICATES,
            VpnProfile.TYPE_USERPASS_PKCS12,
        ).forEach { assertFalse(OpenVPNBackend.needsKeystoreCertificate(profile(it)), "auth type $it") }
    }

    @Test
    fun does_not_flag_keystore_auth_when_an_alias_is_set() {
        assertFalse(OpenVPNBackend.needsKeystoreCertificate(profile(VpnProfile.TYPE_KEYSTORE, "alias")))
    }
}
