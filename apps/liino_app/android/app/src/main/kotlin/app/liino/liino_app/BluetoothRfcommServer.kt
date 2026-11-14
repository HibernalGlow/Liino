package app.liino.liino_app

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import java.io.BufferedReader
import java.io.IOException
import java.io.InputStreamReader
import java.util.UUID

/**
 * Phase 3/Bluetooth spike: RFCOMM server hosted by the phone.
 *
 * The desktop connects out (ADR-0005): it looks the service up by UUID via SDP
 * and opens the channel. For now the session only performs a line handshake so
 * the channel can be verified end-to-end; the audio transport is wired later.
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
            val socket = adapter.listenUsingRfcommWithServiceRecord(SERVICE_NAME, SERVICE_UUID)
            serverSocket = socket
            lastError = null
            isRunning = true
            acceptThread = Thread({ acceptLoop(socket) }, "liino-bt-accept").apply { start() }
            Log.i(TAG, "listening on $SERVICE_UUID")
            true
        } catch (e: SecurityException) {
            fail("Bluetooth permission denied: ${e.message}")
        } catch (e: IOException) {
            fail("Cannot listen on RFCOMM: ${e.message}")
        }
    }

    fun stop() {
        isRunning = false
        closeQuietly(serverSocket)
        serverSocket = null
        closeQuietly(clientSocket)
        clientSocket = null
        acceptThread = null
        Log.i(TAG, "stopped")
    }

    private fun acceptLoop(socket: BluetoothServerSocket) {
        while (isRunning) {
            val client = try {
                socket.accept()
            } catch (e: IOException) {
                if (isRunning) Log.w(TAG, "accept failed: ${e.message}")
                break
            }
            Log.i(TAG, "channel accepted from ${client.remoteDevice?.address}")
            closeQuietly(clientSocket)
            clientSocket = client
            handle(client)
        }
        closeQuietly(serverSocket)
        serverSocket = null
        isRunning = false
    }

    private fun handle(socket: BluetoothSocket) {
        try {
            val reader = BufferedReader(InputStreamReader(socket.inputStream))
            val output = socket.outputStream
            output.write("LIINO-BT-READY\n".toByteArray())
            output.flush()
            while (isRunning) {
                val line = reader.readLine() ?: break
                Log.i(TAG, "rx: $line")
                output.write("echo:$line\n".toByteArray())
                output.flush()
            }
        } catch (e: IOException) {
            if (isRunning) Log.w(TAG, "channel closed: ${e.message}")
        } finally {
            closeQuietly(socket)
            if (clientSocket === socket) clientSocket = null
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
        val SERVICE_UUID: UUID = UUID.fromString("6C69696E-6F00-4B42-8C4C-6C69696E0001")
    }
}
