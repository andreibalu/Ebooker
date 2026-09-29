//
//  OnDeviceSpeechPolicyTests.swift
//  PagelessTests
//

import Speech
import Testing
@testable import Pageless

struct OnDeviceSpeechPolicyTests {
    @Test func rejectsRecognizerWithoutOnDeviceSupport() {
        #expect(throws: OnDeviceSpeechPolicy.PolicyError.unsupported) {
            try OnDeviceSpeechPolicy.requireSupport(false)
        }
    }

    @Test func acceptsRecognizerWithOnDeviceSupport() throws {
        try OnDeviceSpeechPolicy.requireSupport(true)
    }

    @Test @MainActor func carPlayRejectsRecognizerWithoutOnDeviceSupport() {
        #expect(throws: OnDeviceSpeechPolicy.PolicyError.unsupported) {
            try CarPlayVoiceSearch.makeRecognitionRequest(supportsOnDeviceRecognition: false)
        }
    }

    @Test @MainActor func carPlayRequestRequiresLocalRecognitionAndKeepsPartialResults() throws {
        let request = try CarPlayVoiceSearch.makeRecognitionRequest(supportsOnDeviceRecognition: true)
        #expect(request.requiresOnDeviceRecognition)
        #expect(request.shouldReportPartialResults)
    }
}
