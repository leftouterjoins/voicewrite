import Foundation
import IOKit.hid
import os.log

private let headsetLog = OSLog(subsystem: "com.leftouterjoins.VoiceWrite", category: "HeadsetService")

final class HeadsetService: ObservableObject, @unchecked Sendable {
    @MainActor static let shared = HeadsetService()

    @MainActor @Published private(set) var isConnected = false
    @MainActor @Published private(set) var deviceName: String?

    private var hidManager: IOHIDManager?
    private var onButtonDown: (() -> Void)?
    private var onButtonUp: (() -> Void)?
    private var lastButtonState = false
    private let lock = NSLock()

    // HID Telephony Usage Page (0x0B) - used by Teams/Zoom compatible headsets
    private static let kHIDPage_Telephony: Int = 0x0B

    private static func log(_ message: String) {
        #if DEBUG
        print("[HeadsetService] \(message)")
        #endif
    }

    private init() {
        Self.log("[HeadsetService] Initialized")
    }

    func configure(onButtonDown: @escaping () -> Void, onButtonUp: @escaping () -> Void) {
        lock.lock()
        self.onButtonDown = onButtonDown
        self.onButtonUp = onButtonUp
        lock.unlock()
        Self.log("[HeadsetService] Configured with callbacks")
    }

    func start() {
        Self.log("[HeadsetService] start() called")

        guard hidManager == nil else {
            Self.log("[HeadsetService] HID manager already exists")
            return
        }

        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else {
            Self.log("[HeadsetService] Failed to create HID manager")
            return
        }

        // Match any device on the Telephony usage page (Teams/Zoom compatible headsets)
        let telephonyMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: Self.kHIDPage_Telephony
        ]

        IOHIDManagerSetDeviceMatching(manager, telephonyMatch as CFDictionary)
        Self.log("Matching telephony HID devices")

        // Set up device callbacks using a wrapper class to avoid @MainActor issues
        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, result, sender, device in
            guard let ctx = ctx else { return }
            let svc = Unmanaged<HeadsetService>.fromOpaque(ctx).takeUnretainedValue()
            svc.deviceConnected(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, result, sender, device in
            guard let ctx = ctx else { return }
            let svc = Unmanaged<HeadsetService>.fromOpaque(ctx).takeUnretainedValue()
            svc.deviceDisconnected(device)
        }, context)

        IOHIDManagerRegisterInputValueCallback(manager, { ctx, result, sender, value in
            guard let ctx = ctx else { return }
            let svc = Unmanaged<HeadsetService>.fromOpaque(ctx).takeUnretainedValue()
            svc.inputValue(value)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            Self.log("[HeadsetService] Failed to open HID manager: \(result)")
        } else {
            Self.log("[HeadsetService] HID manager opened successfully")
        }
    }

    func stop() {
        guard let manager = hidManager else { return }

        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = nil

        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
            self?.deviceName = nil
        }

        Self.log("[HeadsetService] HID manager stopped")
    }

    // Called from HID callback (not main thread)
    private func deviceConnected(_ device: IOHIDDevice) {
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        let vid = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0

        Self.log("[HeadsetService] Device connected: \(name) (VID: 0x\(String(vid, radix: 16)), PID: 0x\(String(pid, radix: 16)))")

        DispatchQueue.main.async { [weak self] in
            self?.isConnected = true
            self?.deviceName = name
        }
    }

    // Called from HID callback (not main thread)
    private func deviceDisconnected(_ device: IOHIDDevice) {
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        Self.log("[HeadsetService] Device disconnected: \(name)")

        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
            self?.deviceName = nil
        }
    }

    // Called from HID callback (not main thread)
    private func inputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        // Only handle call buttons on Telephony page
        // Usage 0x20 = Hook Switch, 0x21 = Flash (both used for call button)
        guard usagePage == UInt32(Self.kHIDPage_Telephony) else { return }
        guard usage == 0x20 || usage == 0x21 else { return }

        // Only trigger on button press (value=1), not release
        guard intValue == 1 else { return }

        Self.log("Call button pressed (usage=0x\(String(usage, radix: 16)))")

        lock.lock()
        let downCallback = onButtonDown
        lock.unlock()

        Task { @MainActor in
            downCallback?()
        }
    }
}
