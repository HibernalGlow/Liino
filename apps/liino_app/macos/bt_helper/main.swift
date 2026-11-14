// liino-bt-helper: bridges an RFCOMM channel to stdin/stdout.
//
// The Rust daemon spawns this helper (see ADR-0009) and treats stdin/stdout as
// the Bluetooth byte stream. Framing is the caller's responsibility: liino
// writes length-prefixed protobuf frames, the helper forwards raw bytes.
//
// Usage:
//   liino-bt-helper --address f0-2c-7b-fb-ca-9f [--service liino]
//
// Exit codes: 2 missing/invalid address, 3 device not found, 4 service not
// found, 5 channel open failed, 6 stdin/stdout bridge failed.

import Foundation
import IOBluetooth

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data("liino-bt-helper: \(message)\n".utf8))
    exit(code)
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("liino-bt-helper: \(message)\n".utf8))
}

var address: String?
var serviceName = "liino"
var index = 1
let args = CommandLine.arguments
while index < args.count {
    switch args[index] {
    case "--address":
        index += 1
        if index < args.count { address = args[index] }
    case "--service":
        index += 1
        if index < args.count { serviceName = args[index] }
    case "--list":
        for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] {
            log("\(device.addressString ?? "?") \(device.name ?? "?")")
        }
        exit(0)
    default:
        fail("unknown argument \(args[index])", 2)
    }
    index += 1
}

guard let address, !address.isEmpty else {
    fail("missing --address (use --list to inspect paired devices)", 2)
}
guard let device = IOBluetoothDevice(addressString: address) else {
    fail("device not found: \(address)", 3)
}

// Refresh the SDP cache so a service published after pairing is visible.
_ = device.performSDPQuery(nil)
Thread.sleep(forTimeInterval: 1.5)

var channelID: BluetoothRFCOMMChannelID = 0
var found = false
for service in device.services as? [IOBluetoothSDPServiceRecord] ?? [] {
    guard (service.getServiceName() ?? "") == serviceName else { continue }
    if service.getRFCOMMChannelID(&channelID) == kIOReturnSuccess {
        found = true
        break
    }
}
guard found else {
    fail("service '\(serviceName)' not found on \(address)", 4)
}

final class Bridge: NSObject, IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelData(
        _ channel: IOBluetoothRFCOMMChannel!,
        data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        let data = Data(bytes: dataPointer, count: dataLength)
        FileHandle.standardOutput.write(data)
    }

    func rfcommChannelClosed(_ channel: IOBluetoothRFCOMMChannel!) {
        exit(0)
    }
}

let bridge = Bridge()
var channel: IOBluetoothRFCOMMChannel?
let openResult = device.openRFCOMMChannelSync(
    &channel,
    withChannelID: channelID,
    delegate: bridge
)
guard openResult == kIOReturnSuccess, let channel else {
    fail("open channel \(channelID) failed: \(openResult)", 5)
}
log("connected \(address) channel \(channelID)")

let input = Thread {
    let handle = FileHandle.standardInput
    while true {
        let data = handle.availableData
        if data.isEmpty {
            _ = channel.close()
            exit(0)
        }
        let written: IOReturn = data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return kIOReturnError }
            return channel.writeSync(
                UnsafeMutableRawPointer(mutating: base),
                length: UInt16(data.count)
            )
        }
        if written != kIOReturnSuccess {
            fail("write failed: \(written)", 6)
        }
    }
}
input.start()

RunLoop.main.run()
