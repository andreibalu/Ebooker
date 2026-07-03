//
//  OnDeviceSpeechPolicyTests.swift
//  PagelessTests
//

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
}
