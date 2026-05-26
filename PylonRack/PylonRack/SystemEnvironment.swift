import Foundation

// Protocol that abstracts macOS system calls so they can be mocked in tests.
// Production implementation uses NSApp + SMAppService.
// Test implementation does nothing or records calls.

protocol SystemEnvironment {
    func setDockVisibility(_ visible: Bool)
    func setLaunchAtLogin(_ enabled: Bool)
}

// MARK: - Production

import AppKit
import ServiceManagement

struct MacSystemEnvironment: SystemEnvironment {

    func setDockVisibility(_ visible: Bool) {
        NSApp?.setActivationPolicy(visible ? .regular : .accessory)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled { try service.unregister() }
            }
        } catch {
            // Non-fatal: user may not have granted permission yet.
        }
    }
}
