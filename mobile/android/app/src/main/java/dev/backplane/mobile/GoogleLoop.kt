package dev.backplane.mobile

import android.content.Context
import android.content.Intent
import android.net.Uri
import java.net.InetAddress
import java.net.ServerSocket
import kotlin.concurrent.thread

// Google's sign-in from the phone (RFC 8252 7.3, docs/bots.md "Google"):
// a listener on a loopback port of the app's own, the hub asked to begin
// with that redirect ("connect@<port>"), Google's page in the browser, and
// the address Google sent the browser back to handed to the hub
// ("done:<address>"), which trades the code. The page it answers sends the
// browser back to the app (backplane://google). The hub keeps the
// accounts; each sign-in adds one.
object GoogleLoop {
    private var server: ServerSocket? = null
    private var port = 0
    private var opened = false

    @Synchronized
    fun start(act: (String, String) -> Unit) {
        stop()
        val s = runCatching { ServerSocket(0, 1, InetAddress.getByName("127.0.0.1")) }.getOrNull()
        if (s == null) { act("google", "connect"); return }
        server = s
        port = s.localPort
        val p = port
        thread(isDaemon = true, name = "google-loop") {
            while (true) {
                val c = runCatching { s.accept() }.getOrNull() ?: break
                val path = runCatching {
                    c.soTimeout = 10000
                    val line = c.getInputStream().bufferedReader().readLine() ?: ""
                    line.split(" ").getOrNull(1) ?: ""
                }.getOrDefault("")
                if (!path.startsWith("/oauth/google?")) {
                    runCatching { c.getOutputStream().write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".toByteArray()); c.close() }
                    continue
                }
                val page = "<!doctype html><meta name=viewport content=\"width=device-width\"><title>Backplane</title>" +
                    "<p style=\"font:16px sans-serif;margin:24px\">Signed in. <a href=\"backplane://google\">Back to Backplane</a></p>" +
                    "<script>location.href='backplane://google'</script>"
                val body = page.toByteArray()
                runCatching {
                    c.getOutputStream().write(("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: ${body.size}\r\n" +
                        "Cache-Control: no-store\r\nConnection: close\r\n\r\n").toByteArray() + body)
                    c.close()
                }
                act("google", "done:http://127.0.0.1:$p$path")
                stopIf(s)
                break
            }
        }
        act("google", "connect@$p")
    }

    // the hub's sign-in link: opened once, when it sends Google back here
    @Synchronized
    fun open(ctx: Context, link: String) {
        if (server == null || opened || port == 0 || link.isEmpty()) return
        val u = Uri.parse(link)
        if (u.getQueryParameter("redirect_uri") != "http://127.0.0.1:$port/oauth/google") return
        opened = true
        runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, u).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }

    @Synchronized
    private fun stopIf(s: ServerSocket) {
        if (server === s) stop()
    }

    @Synchronized
    fun stop() {
        runCatching { server?.close() }
        server = null
        port = 0
        opened = false
    }
}
