package app.liino.liino_app

import android.Manifest
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.UUID

/**
 * RFCOMM server hosted by the phone.
 *
 * The desktop connects out (ADR-0005 / ADR-0009): it looks the service up by
 * UUID/name via SDP and opens the channel. Locally, a loopback TCP relay on
 * `127.0.0.1:8555` bridges the Rust `startSender` stream directly onto the
 * accepted `BluetoothSocket` so framed audio packets flow end-to-end.
 */
class BluetoothRfcommServer(private val context: Context) {
    @Volatile
    var isRunning: Boolean = false
        private set

    @Volatile
    var lastError: String? = null
        private set

    private var serverSocket: BluetoothServerSocket? = null
    private var clientSocket: BluetoothSocket? = null
    private var localRelayServer: ServerSocket? = null
    private var localRelayClient: Socket? = null
    private var acceptThread: Thread? = null

    fun start(): Boolean {
        if (isRunning) return true

        val manager = context.getSystemService(BluetoothManager::class.java)
        val adapter = manager?.adapter
        if (adapter == null) return fail("This device has no Bluetooth adapter")
        if (!adapter.isEnabled) return fail("Bluetooth is turned off")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return fail("BLUETOOTH_CONNECT permission is not granted")
        }

        return try {
            val relay = ServerSocket(LOCAL_RELAY_PORT, 1, InetAddress.getByName("127.0.0.1"))
            relay.reuseAddress = true
            localRelayServer = relay

            val socket = adapter.listenUsingRfcommWithServiceRecord(SERVICE_NAME, SERVICE_UUID)
            serverSocket = socket
            lastError = null
            isRunning = true
            acceptThread = Thread({ acceptLoop(socket, relay) }, "liino-bt-accept").apply { start() }
            Log.i(TAG, "listening on $SERVICE_UUID (local relay 127.0.0.1:$LOCAL_RELAY_PORT)")
            true
        } catch (e: SecurityException) {
            closeQuietly(localRelayServer)
            localRelayServer = null
            fail("Bluetooth permission denied: ${e.message}")
        } catch (e: IOException) {
            closeQuietly(localRelayServer)
            localRelayServer = null
            fail("Cannot listen on RFCOMM: ${e.message}")
        }
    }

    fun stop() {
        isRunning = false
        closeQuietly(serverSocket)
        serverSocket = null
        closeQuietly(clientSocket)
        clientSocket = null
        closeQuietly(localRelayServer)
        localRelayServer = null
        closeQuietly(localRelayClient)
        localRelayClient = null
        acceptThread = null
        Log.i(TAG, "stopped")
    }

    private fun acceptLoop(btServer: BluetoothServerSocket, relayServer: ServerSocket) {
        while (isRunning) {
            val client = try {
                btServer.accept()
            } catch (e: IOException) {
                if (isRunning) Log.w(TAG, "accept failed: ${e.message}")
                break
            }
            Log.i(TAG, "channel accepted from ${client.remoteDevice?.address}")
            closeQuietly(clientSocket)
            clientSocket = client
            bridgeToLocalSender(client, relayServer)
        }
        closeQuietly(btServer)
        serverSocket = null
        isRunning = false
    }

    private fun bridgeToLocalSender(btSocket: BluetoothSocket, relayServer: ServerSocket) {
        try {
            val tcpSocket = relayServer.accept()
            tcpSocket.tcpNoDelay = true
            closeQuietly(localRelayClient)
            localRelayClient = tcpSocket
            Log.i(TAG, "paired RFCOMM channel with local sender 127.0.0.1:$LOCAL_RELAY_PORT")

            val uplink = Thread({
                pumpBytes(tcpSocket.getInputStream(), btSocket.outputStream, "tcp->bt")
                closeQuietly(btSocket)
                closeQuietly(tcpSocket)
            }, "liino-bt-uplink").apply { start() }

            pumpBytes(btSocket.inputStream, tcpSocket.getOutputStream(), "bt->tcp")
            closeQuietly(btSocket)
            closeQuietly(tcpSocket)
            uplink.join(500)
        } catch (e: IOException) {
            if (isRunning) Log.w(TAG, "bridge closed: ${e.message}")
        } finally {
            closeQuietly(btSocket)
            if (clientSocket === btSocket) clientSocket = null
        }
    }

    private fun pumpBytes(input: InputStream, output: OutputStream, label: String) {
        val buffer = ByteArray(4096)
        try {
            while (isRunning) {
                val read = input.read(buffer)
                if (read <= 0) break
                output.write(buffer, 0, read)
                output.flush()
            }
        } catch (e: IOException) {
            if (isRunning) Log.d(TAG, "$label ended: ${e.message}")
        }
    }

    private fun fail(message: String): Boolean {
        lastError = message
        isRunning = false
        Log.w(TAG, message)
        return false
    }

    private fun closeQuietly(closeable: java.io.Closeable?) {
        try {
            closeable?.close()
        } catch (_: IOException) {
        }
    }

    companion object {
        private const val TAG = "liino-bt"
        private const val SERVICE_NAME = "liino"
        const val LOCAL_RELAY_PORT = 8555
        val SERVICE_UUID: UUID = UUID.fromString("6C69696E-6F00-4B42-8C4C-6C69696E0001")
    }
}
