package com.meshcentral.htcommander

import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator

/**
 * Entry point for the Android Auto car UI.
 *
 * Declared in AndroidManifest.xml with the `androidx.car.app.CarAppService`
 * intent filter and the `androidx.car.app.category.IOT` category. The host
 * (Android Auto / the Desktop Head Unit) binds to this service and drives the
 * screens returned by [RadioSession].
 */
class RadioCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator {
        // Allow any host so the app works in the Desktop Head Unit and on real
        // head units during development. For a production release, switch to the
        // default validator backed by an allowlist (res/xml/hosts_allowlist).
        return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
    }

    override fun onCreateSession(): Session = RadioSession()
}
