//
//  TrackingRuntime.swift
//  pointer Watch App
//

import Foundation
import WatchKit
import os

/// Keeps the Watch app alive while tracking (WKExtendedRuntimeSession).
final class TrackingRuntime: NSObject, WKExtendedRuntimeSessionDelegate {
    private let log = Logger(subsystem: "bp.pointer.watch", category: "Runtime")
    private var session: WKExtendedRuntimeSession?
    private var wantRunning = false
    private var restartWork: DispatchWorkItem?
    var onWillExpire: (() -> Void)?
    private(set) var isActive = false
    private(set) var lastError: String?

    func start() {
        wantRunning = true
        beginSession()
    }

    func stop() {
        wantRunning = false
        restartWork?.cancel()
        restartWork = nil
        session?.invalidate()
        session = nil
        isActive = false
        log.notice("extended runtime stopped by user")
    }

    private func beginSession() {
        guard wantRunning else { return }
        if session?.state == .running { return }
        session?.invalidate()
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        session = s
        s.start()
        log.notice("extended runtime start requested")
    }

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        isActive = true
        lastError = nil
        log.notice("extended runtime running")
    }

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        log.notice("extended runtime will expire")
        onWillExpire?()
        // Overlap restart before invalidation.
        DispatchQueue.main.async { [weak self] in
            self?.beginSession()
        }
    }

    func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        isActive = false
        if let error {
            lastError = error.localizedDescription
            log.error("runtime invalidate: \(error.localizedDescription, privacy: .public)")
        } else {
            lastError = "session ended (\(reason.rawValue))"
            log.notice("runtime invalidate reason=\(reason.rawValue)")
        }
        guard wantRunning else { return }
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.beginSession()
        }
        restartWork = work
        // Brief delay then re-request so tracking can continue until user stops.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
