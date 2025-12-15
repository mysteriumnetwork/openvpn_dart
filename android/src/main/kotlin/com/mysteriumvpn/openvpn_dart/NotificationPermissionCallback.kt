package com.mysteriumvpn.openvpn_dart

interface NotificationPermissionCallback {
    fun onResult(permissionStatus: NotificationPermission)
    fun onError(exception: Exception)
}
