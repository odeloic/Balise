//
//  TerminationSignalTests.swift
//  BaliseTests
//

import Foundation
import Testing
@testable import Balise

@Suite("TerminationSignal")
struct TerminationSignalTests {

    @Test("each signal maps to the right POSIX number")
    func signalNumbers() {
        #expect(TerminationSignal.terminate.signalNumber == SIGTERM)
        #expect(TerminationSignal.forceKill.signalNumber == SIGKILL)
    }

    /// Force quit loses unsaved work, so it never happens without a prompt.
    @Test("only force quit needs confirming")
    func confirmation() {
        #expect(!TerminationSignal.terminate.needsConfirmation)
        #expect(TerminationSignal.forceKill.needsConfirmation)
    }

    @Test("labels read as buttons")
    func labels() {
        #expect(TerminationSignal.terminate.label == "Quit")
        #expect(TerminationSignal.forceKill.label == "Force Quit")
    }

    @Test("there are exactly two ways to stop something")
    func caseCount() {
        #expect(TerminationSignal.allCases.count == 2)
    }
}

@Suite("ProcessControlError")
struct ProcessControlErrorTests {

    @Test("every failure explains itself in plain words", arguments: [
        (ProcessControlError.notPermitted(name: "cupsd"),
         "cupsd belongs to another user. Balise cannot stop it."),
        (.noSuchProcess(name: "node"), "node had already stopped."),
        (.ignored(name: "mongod"), "mongod ignored the request to quit."),
    ])
    func descriptions(error: ProcessControlError, expected: String) {
        #expect(error.errorDescription == expected)
        #expect(error.localizedDescription == expected)
    }
}
