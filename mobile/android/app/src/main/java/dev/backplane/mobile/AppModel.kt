package dev.backplane.mobile

import android.app.Application
import androidx.lifecycle.AndroidViewModel

// The screen's view of the app's one client (Core): reads its state and
// passes the user's actions through. Holds nothing of its own.
class AppModel(app: Application) : AndroidViewModel(app) {
    private val core = app.core

    val links get() = core.links
    val screen get() = core.screen
    val composer get() = core.composer
    val scrolls get() = core.scrolls
    val jump get() = core.jump
    val plots get() = core.plots
    var picking
        get() = core.picking
        set(v) { core.picking = v }

    fun pair(text: String) = core.pair(text)
    fun unpair(key: String) = core.unpair(key)
    fun act(action: String, value: String = "") = core.act(action, value)
    fun quiet(action: String, value: String) = core.quiet(action, value)
    fun draft(text: String) = core.draft(text)
    val cats get() = core.cats
    fun cat(key: String) = core.cat(key)
    fun field(name: String, text: String) = core.field(name, text)
    fun web(path: String) = core.web(path)
    fun attach(data: ByteArray, name: String) = core.attach(data, name)
    fun hubUrl(path: String, query: String = "", token: Boolean = true) = core.hubUrl(path, query, token)
}
