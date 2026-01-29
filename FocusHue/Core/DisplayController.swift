//
//  DisplayController.swift
//  FocusHue
//
//  Controls system-wide grayscale using private MediaAccessibility framework
//

import Foundation
import Combine

@Observable
final class DisplayController {
    private(set) var isGrayscaleEnabled: Bool = false
    private(set) var transitionProgress: Double = 0.0
    private(set) var isTransitioning: Bool = false

    private var transitionTimer: Timer?
    private var testTimer: Timer?
    private let transitionDuration: TimeInterval = 15.0
    private let timerInterval: TimeInterval = 0.1

    // Filter constants from MediaAccessibility (defined in Bridge.h)
    // SYSTEM_FILTER = 0x1, GRAYSCALE_TYPE = 0x1, UNIVERSALACCESSD_MAGIC = 0x8

    init() {
        // Check initial grayscale state
        isGrayscaleEnabled = grayscaleEnabled()
    }

    deinit {
        // Ensure grayscale is disabled when the controller is destroyed
        disableGrayscale()
    }

    // MARK: - Public API

    func enableGrayscale() {
        MADisplayFilterPrefSetCategoryEnabled(SYSTEM_FILTER, true)
        MADisplayFilterPrefSetType(SYSTEM_FILTER, GRAYSCALE_TYPE)
        _UniversalAccessDStart(UNIVERSALACCESSD_MAGIC)
        isGrayscaleEnabled = true
    }

    func disableGrayscale() {
        MADisplayFilterPrefSetCategoryEnabled(SYSTEM_FILTER, false)
        _UniversalAccessDStart(UNIVERSALACCESSD_MAGIC)
        isGrayscaleEnabled = false
    }

    func grayscaleEnabled() -> Bool {
        return MADisplayFilterPrefGetCategoryEnabled(SYSTEM_FILTER)
    }

    /// Test grayscale for a specified duration, then restore original state
    func testGrayscale(duration: TimeInterval = 5.0) {
        let wasEnabled = isGrayscaleEnabled
        enableGrayscale()

        testTimer?.invalidate()
        testTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if !wasEnabled {
                self.disableGrayscale()
            }
            self.testTimer = nil
        }
    }

    /// Start a gradual transition to grayscale with a progress indicator
    /// The actual grayscale is binary, but we show progress to the user
    func startGradualTransition(toGrayscale: Bool) {
        transitionTimer?.invalidate()

        if toGrayscale {
            isTransitioning = true
            transitionProgress = 0.0

            let totalSteps = transitionDuration / timerInterval
            let progressIncrement = 1.0 / totalSteps

            transitionTimer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }

                self.transitionProgress += progressIncrement

                if self.transitionProgress >= 1.0 {
                    timer.invalidate()
                    self.transitionProgress = 1.0
                    self.enableGrayscale()
                    self.isTransitioning = false
                    self.transitionTimer = nil
                }
            }
        } else {
            // Cancel any ongoing transition and disable grayscale
            cancelTransition()
            disableGrayscale()
        }
    }

    /// Cancel an ongoing transition
    func cancelTransition() {
        transitionTimer?.invalidate()
        transitionTimer = nil
        isTransitioning = false
        transitionProgress = 0.0
    }

    /// Reset display to normal (disable grayscale and cancel transitions)
    func reset() {
        cancelTransition()
        disableGrayscale()
    }
}
