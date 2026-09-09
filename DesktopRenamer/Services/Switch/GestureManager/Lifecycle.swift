import AppKit
import Combine
import Foundation
import IOKit

extension GestureManager {

    // Dynamically loads the private MultitouchSupport framework.
    func loadPrivateFramework() {
        guard let handle = dlopen(MTSFrameworkPath, RTLD_NOW) else {
            print("Failed to load MultitouchSupport.framework at \(MTSFrameworkPath)")
            return
        }

        // Resolve private C function symbols.
        if let sym = dlsym(handle, "MTDeviceCreateList") {
            _MTDeviceCreateList = unsafeBitCast(
                sym, to: (@convention(c) () -> Unmanaged<CFArray>).self)
        }
        if let sym = dlsym(handle, "MTDeviceCreateFromService") {
            _MTDeviceCreateFromService = unsafeBitCast(
                sym, to: (@convention(c) (io_service_t) -> MTDeviceRef).self)
        }
        if let sym = dlsym(handle, "MTRegisterContactFrameCallback") {
            _MTRegisterContactFrameCallback = unsafeBitCast(
                sym,
                to: (@convention(c) (
                    MTDeviceRef,
                    @convention(c) (MTDeviceRef, UnsafeMutableRawPointer, Int32, Double, Int32) ->
                        Void, Int32
                ) -> Void).self)
        }
        if let sym = dlsym(handle, "MTDeviceStart") {
            _MTDeviceStart = unsafeBitCast(
                sym, to: (@convention(c) (MTDeviceRef, Int32) -> Void).self)
        }
        if let sym = dlsym(handle, "MTDeviceStop") {
            _MTDeviceStop = unsafeBitCast(
                sym, to: (@convention(c) (MTDeviceRef, Int32) -> Void).self)
        }
    }

    // Lifecycle management for multitouch devices.
    func startMonitoring() {
        if let createList = _MTDeviceCreateList {
            let deviceList = createList().takeRetainedValue() as? [MTDeviceRef] ?? []
            for device in deviceList {
                setupDevice(device)
            }
        }
        setupIOKitListener()
        print("GestureManager: Started monitoring. Current devices: \(devices.count)")
    }

    func stopMonitoring() {
        guard let stopDevice = _MTDeviceStop else { return }
        for device in devices {
            stopDevice(device, 0)
        }
        devices.removeAll()

        if addedIterator != 0 {
            IOObjectRelease(addedIterator)
            addedIterator = 0
        }
        if let port = notifyPort {
            IONotificationPortDestroy(port)
            notifyPort = nil
        }

        print("GestureManager: Stopped monitoring.")
    }

    func setupDevice(_ device: MTDeviceRef) {
        if !devices.contains(device) {
            devices.append(device)
            if let registerCallback = _MTRegisterContactFrameCallback,
                let startDevice = _MTDeviceStart
            {
                registerCallback(device, mtCallback, 0)
                startDevice(device, 0)
                print("GestureManager: Registered device \(device)")
            }
        }
    }

    // Registers for IOKit notifications to detect hardware arrival events.
    func setupIOKitListener() {
        guard notifyPort == nil else { return }

        let port = IONotificationPortCreate(kIOMainPortDefault)
        self.notifyPort = port

        guard let runLoopSource = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue()
        else { return }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

        let matchingDict = IOServiceMatching("AppleMultitouchDevice")

        let context = Unmanaged.passUnretained(self).toOpaque()

        let result = IOServiceAddMatchingNotification(
            port,
            kIOFirstMatchNotification,
            matchingDict,
            ioKitCallback,
            context,
            &addedIterator
        )

        if result == kIOReturnSuccess {
            consumeIterator(addedIterator)
        }
    }

    func consumeIterator(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let createFromService = _MTDeviceCreateFromService {
                let device = createFromService(service)
                setupDevice(device)
            }
            IOObjectRelease(service)
        }
    }

}
