//
//  LocalServerDiscovery.swift
//  SportsCal
//
//  Created by Claude on 2026-02-12.
//

import Foundation
import Network
import os

@MainActor
@Observable
final class LocalServerDiscovery {
    var discoveredHost: String?
    var isSearching: Bool = false

    private var browser: NWBrowser?
    private var connection: NWConnection?

    func start() {
        guard browser == nil else { return }
        isSearching = true
        discoveredHost = nil

        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_sportscal._tcp", domain: nil), using: params)

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .failed(let error):
                    AppLogger.discovery.error("Bonjour browser failed: \(error)")
                    self?.isSearching = false
                case .cancelled:
                    self?.isSearching = false
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self else { return }
                if let result = results.first {
                    self.resolve(result: result)
                } else {
                    self.discoveredHost = nil
                }
            }
        }

        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
        discoveredHost = nil
        isSearching = false
    }

    private func resolve(result: NWBrowser.Result) {
        connection?.cancel()
        let connection = NWConnection(to: result.endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    if let path = connection.currentPath,
                       let endpoint = path.remoteEndpoint {
                        switch endpoint {
                        case .hostPort(let host, let port):
                            let hostString: String
                            switch host {
                            case .ipv4(let addr):
                                // Strip zone ID suffix (e.g. "%en0") — invalid in URLs
                                let raw = "\(addr)"
                                hostString = raw.split(separator: "%").first.map(String.init) ?? raw
                            case .ipv6(let addr):
                                let raw = "\(addr)"
                                let stripped = raw.split(separator: "%").first.map(String.init) ?? raw
                                if stripped == "::1" {
                                    hostString = "127.0.0.1"
                                } else {
                                    hostString = "[\(stripped)]"
                                }
                            case .name(let name, _):
                                hostString = name
                            @unknown default:
                                let raw = "\(host)"
                                hostString = raw.split(separator: "%").first.map(String.init) ?? raw
                            }
                            self.discoveredHost = "\(hostString):\(port)"
                            self.isSearching = false
                            AppLogger.discovery.info("Bonjour: discovered local server at \(self.discoveredHost!)")
                        default:
                            break
                        }
                    }
                case .failed:
                    self.discoveredHost = nil
                    connection.cancel()
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
        self.connection = connection
    }
}
