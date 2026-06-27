// SessionDiscovery.swift
// Bonjour/mDNS browser for SessionPad services on the local network.

import Foundation
import Network
import os.log

struct DiscoveredService: Equatable, Sendable, Identifiable {
    let name: String
    let endpoint: NWEndpoint
    let protocolVersion: Int?
    let sessionName: String?

    var id: String { name }

    /// Host label from Bonjour instance name, e.g. "SessionPad (MyMac)" → "MyMac".
    var displayHostName: String {
        let prefix = "SessionPad ("
        let suffix = ")"
        if name.hasPrefix(prefix), name.hasSuffix(suffix) {
            let start = name.index(name.startIndex, offsetBy: prefix.count)
            let end = name.index(name.endIndex, offsetBy: -suffix.count)
            return String(name[start..<end])
        }
        return name
    }

    var displaySubtitle: String? {
        guard let sessionName, !sessionName.isEmpty else { return nil }
        return sessionName
    }
}

protocol SessionDiscoveryDelegate: AnyObject {
    func discovery(_ discovery: SessionDiscovery, didFind service: DiscoveredService)
    func discovery(_ discovery: SessionDiscovery, didLose service: DiscoveredService)
    func discoveryStateChanged(_ discovery: SessionDiscovery, isSearching: Bool)
}

final class SessionDiscovery: @unchecked Sendable {

    weak var delegate: SessionDiscoveryDelegate?

    private let log = OSLog(subsystem: "com.scharovsky.SessionPad", category: "Discovery")
    private let queue = DispatchQueue(label: "com.scharovsky.SessionPad.discovery")
    private var browser: NWBrowser?
    private var discovered: [String: DiscoveredService] = [:]
    private(set) var isSearching = false

    func start() {
        queue.async { [weak self] in
            self?.startBrowser()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.browser?.cancel()
            self?.browser = nil
            self?.discovered.removeAll()
            self?.setSearching(false)
        }
    }

    func bestService() -> DiscoveredService? {
        queue.sync {
            discovered.values.sorted { $0.name < $1.name }.first
        }
    }

    func snapshot() -> [DiscoveredService] {
        queue.sync {
            discovered.values.sorted { $0.name < $1.name }
        }
    }

    private func startBrowser() {
        browser?.cancel()
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let descriptor = NWBrowser.Descriptor.bonjour(type: SPProtocol.serviceType, domain: nil)
        let browser = NWBrowser(for: descriptor, using: params)
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.setSearching(true)
            case .failed, .cancelled:
                self.setSearching(false)
            default:
                break
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            self?.handleBrowseResults(results: results, changes: changes)
        }

        browser.start(queue: queue)
        os_log(.info, log: log, "Bonjour browser started for %{public}@", SPProtocol.serviceType)
    }

    private func handleBrowseResults(results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                addResult(result)
            case .removed(let result):
                removeResult(result)
            default:
                break
            }
        }
    }

    private func addResult(_ result: NWBrowser.Result) {
        guard case .service(let name, _, _, _) = result.endpoint else { return }
        let key = name
        var protocolVersion: Int?
        var sessionName: String?
        if case .bonjour(let txtRecord) = result.metadata {
            if let v = txtRecord["v"], let parsed = Int(v) {
                protocolVersion = parsed
            }
            sessionName = txtRecord["name"]
        }
        let service = DiscoveredService(
            name: name,
            endpoint: result.endpoint,
            protocolVersion: protocolVersion,
            sessionName: sessionName
        )
        discovered[key] = service
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.discovery(self, didFind: service)
        }
    }

    private func removeResult(_ result: NWBrowser.Result) {
        guard case .service(let name, _, _, _) = result.endpoint else { return }
        guard let service = discovered.removeValue(forKey: name) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.discovery(self, didLose: service)
        }
    }

    private func setSearching(_ searching: Bool) {
        isSearching = searching
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.discoveryStateChanged(self, isSearching: searching)
        }
    }
}
