//
//  TingMoTests.swift
//  TingMoTests
//
//  Created by Kenton Wang on 2026/5/11.
//

import Testing
@testable import TingMo

struct TingMoTests {
    @Test func excludesCoreAudioDefaultAggregateDevices() {
        #expect(
            !AudioDeviceEnumerator.isUserSelectableDevice(
                uid: "CADefaultDeviceAggregate-71548-0",
                name: "CADefaultDeviceAggregate-71548-0"
            )
        )
    }

    @Test func includesUserCreatedAggregateDevices() {
        #expect(
            AudioDeviceEnumerator.isUserSelectableDevice(
                uid: "com.example.studio-aggregate",
                name: "Studio Aggregate"
            )
        )
    }
}
