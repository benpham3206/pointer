//
//  WorkoutKeepAlive.swift
//  pointer Watch App
//

import Foundation
import HealthKit
import os

/// Keeps tracking alive under watchOS workout execution rules.
@MainActor
final class WorkoutKeepAlive: NSObject, HKWorkoutSessionDelegate {
    static let shared = WorkoutKeepAlive()

    private let healthStore = HKHealthStore()
    private let log = Logger(subsystem: "bp.pointer.watch", category: "WorkoutKeepAlive")
    private var session: HKWorkoutSession?
    private var authorizationTask: Task<Void, Never>?
    private var wantRunning = false
    private var didFallBack = false

    var onFailure: ((_ rootCause: String, _ failureType: String) -> Void)?
    var fallback: (() -> Void)?
    private(set) var isActive = false
    private(set) var lastError: String?

    func start() {
        guard !wantRunning else { return }
        wantRunning = true
        didFallBack = false
        lastError = nil

        guard HKHealthStore.isHealthDataAvailable() else {
            fail(rootCause: "HealthKit is unavailable on this watch", failureType: "healthKitUnavailable")
            return
        }

        let workoutType = HKObjectType.workoutType()
        authorizationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await healthStore.requestAuthorization(toShare: [workoutType], read: [])
                guard !Task.isCancelled, wantRunning else { return }
                guard healthStore.authorizationStatus(for: workoutType) == .sharingAuthorized else {
                    fail(rootCause: "HealthKit workout authorization was denied", failureType: "authorizationDenied")
                    return
                }
                beginSession()
            } catch {
                guard !Task.isCancelled, wantRunning else { return }
                fail(rootCause: error.localizedDescription, failureType: "authorizationFailure")
            }
        }
    }

    func stop() {
        wantRunning = false
        authorizationTask?.cancel()
        authorizationTask = nil
        session?.end()
        session = nil
        isActive = false
        log.notice("workout keep-alive stopped by user")
    }

    private func beginSession() {
        guard wantRunning else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .indoor

        do {
            let workoutSession = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: configuration
            )
            workoutSession.delegate = self
            session = workoutSession
            workoutSession.startActivity(with: Date())
            log.notice("workout keep-alive start requested")
        } catch {
            fail(rootCause: error.localizedDescription, failureType: "sessionStartFailure")
        }
    }

    private func fail(rootCause: String, failureType: String) {
        guard wantRunning, !didFallBack else { return }
        didFallBack = true
        isActive = false
        lastError = rootCause
        session?.end()
        session = nil
        log.error("workout keep-alive [\(failureType, privacy: .public)]: \(rootCause, privacy: .public)")
        onFailure?(rootCause, failureType)
        fallback?()
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor [weak self] in
            guard let self, workoutSession === session else { return }
            switch toState {
            case .running:
                isActive = true
                lastError = nil
                log.notice("workout keep-alive running")
            case .ended:
                isActive = false
                if wantRunning {
                    fail(rootCause: "Workout session ended unexpectedly", failureType: "sessionEnded")
                }
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, workoutSession === session else { return }
            fail(rootCause: error.localizedDescription, failureType: "sessionFailure")
        }
    }
}
