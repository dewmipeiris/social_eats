//
//  NetworkMonitor.swift
//  SocialEats
//
//  Watches the internet connection with NWPathMonitor.
//  When offline, the app shows an "offline" banner and reads
//  passes and tables from the Core Data cache instead.
//

import Foundation
import Network

final class NetworkMonitor: ObservableObject {
    @Published private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "socialeats.network")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = (path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
