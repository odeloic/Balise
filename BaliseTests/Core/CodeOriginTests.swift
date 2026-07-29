//
//  CodeOriginTests.swift
//  BaliseTests
//

import Foundation
import Testing
@testable import Balise

@Suite("CodeOrigin")
struct CodeOriginTests {

    @Test("labels fit on a badge", arguments: [
        (CodeOrigin.apple, "Apple"),
        (.appStore(bundleID: "com.foo.bar"), "App Store"),
        (.developerID(teamID: "M7LAPNZ2X6", teamName: "Acme Inc"), "Acme Inc"),
        (.adHoc, "Ad Hoc"),
        (.unsigned, "Unsigned"),
        (.unreadable(reason: "operation not permitted"), "Unknown"),
    ])
    func labels(origin: CodeOrigin, expected: String) {
        #expect(origin.label == expected)
    }

    @Test("a developer with no name still reads as identified")
    func namelessDeveloper() {
        #expect(CodeOrigin.developerID(teamID: "M7LAPNZ2X6", teamName: nil).label
                == "Identified Developer")
    }

    @Test("trust ranks system above identified above anonymous above unknown")
    func trustOrder() {
        #expect(CodeOrigin.apple.trust == .system)
        #expect(CodeOrigin.appStore(bundleID: nil).trust == .system)
        #expect(CodeOrigin.developerID(teamID: "X", teamName: nil).trust == .identified)
        #expect(CodeOrigin.adHoc.trust == .anonymous)
        #expect(CodeOrigin.unsigned.trust == .anonymous)
        #expect(CodeOrigin.unreadable(reason: "").trust == .unknown)

        #expect(TrustLevel.unknown < .anonymous)
        #expect(TrustLevel.anonymous < .identified)
        #expect(TrustLevel.identified < .system)
    }
}
