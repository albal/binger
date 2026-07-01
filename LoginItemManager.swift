//
//  LoginItemManager.swift
//  binger
//

import Foundation
import Observation
import ServiceManagement

@Observable
final class LoginItemManager {
    private(set) var isEnabled: Bool = false
    private(set) var errorMessage: String?

    private let service = SMAppService.mainApp

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = service.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }
}
