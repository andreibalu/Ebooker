//
//  OnDeviceSpeechPolicyTests.swift
//  PagelessTests
//

import Testing
@testable import Pageless

struct OnDeviceSpeechPolicyTests {
    @Test func requiresOnDeviceRecognizerSupport() throws {
        #expect(throws: OnDeviceSpeechPolicy.PolicyError.unsupported) {
            try OnDeviceSpeechPolicy.requireSupport(false)
        }
        try OnDeviceSpeechPolicy.requireSupport(true)
    }
}
