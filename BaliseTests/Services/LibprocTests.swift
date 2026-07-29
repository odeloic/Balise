//
//  LibprocTests.swift
//  BaliseTests
//
//  The parts of the C layer that decide something, tested without the kernel.
//

import Darwin
import Foundation
import Testing
@testable import Balise

@Suite("Libproc byte handling")
struct LibprocByteTests {

    @Test("a port is read out of network byte order")
    func portByteOrder() {
        // 5432 is 0x1538. Sent big-endian, it lands in an int as 0x3815.
        #expect(Libproc.hostPort(0x3815) == 5432)
        #expect(Libproc.hostPort(0x5000) == 80)
        #expect(Libproc.hostPort(0) == 0)
    }

    @Test("high ports survive the conversion")
    func highPort() {
        let raw = Int32(UInt16(57621).bigEndian)
        #expect(Libproc.hostPort(raw) == 57621)
    }

    @Test("a C string stops at the first zero byte")
    func textStopsAtZero() {
        let bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (110, 111, 100, 101, 0, 88)
        #expect(Libproc.text(bytes) == "node")
    }

    /// `pbi_comm` is sixteen bytes and a long name fills every one of them.
    /// Reading past the array would be a buffer overrun.
    @Test("a full array with no terminator is still read safely")
    func textWithoutTerminator() {
        let bytes: (UInt8, UInt8, UInt8, UInt8) = (112, 111, 115, 116)
        #expect(Libproc.text(bytes) == "post")
    }

    @Test("an empty array reads as an empty string")
    func emptyText() {
        let bytes: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
        #expect(Libproc.text(bytes).isEmpty)
    }
}

@Suite("Libproc argument parsing")
struct LibprocArgumentTests {

    /// Builds the shape `KERN_PROCARGS2` hands back: a count, the executable
    /// path, padding zeros, then that many null-terminated strings.
    private func buffer(count: Int32, executablePath: String, padding: Int, arguments: [String]) -> [UInt8] {
        var bytes = withUnsafeBytes(of: count) { Array($0) }
        bytes += Array(executablePath.utf8) + [0]
        bytes += [UInt8](repeating: 0, count: padding)
        for argument in arguments { bytes += Array(argument.utf8) + [0] }
        return bytes
    }

    @Test("reads the command line back out")
    func parsesArguments() throws {
        let bytes = buffer(
            count: 4,
            executablePath: "/opt/homebrew/bin/node",
            padding: 3,
            arguments: ["node", "server.js", "--port", "6006"]
        )
        let parsed = try #require(Libproc.parseArguments(bytes, byteCount: bytes.count))

        #expect(parsed == ["node", "server.js", "--port", "6006"])
    }

    @Test("stops at the count, ignoring the environment that follows")
    func stopsAtArgumentCount() throws {
        var bytes = buffer(count: 1, executablePath: "/usr/bin/ssh", padding: 1, arguments: ["ssh"])
        bytes += Array("PATH=/usr/bin".utf8) + [0]

        #expect(try #require(Libproc.parseArguments(bytes, byteCount: bytes.count)) == ["ssh"])
    }

    @Test("an argument with spaces stays one argument")
    func spacesInAnArgument() throws {
        let bytes = buffer(count: 2, executablePath: "/bin/sh", padding: 1,
                           arguments: ["sh", "-c echo hello world"])
        #expect(try #require(Libproc.parseArguments(bytes, byteCount: bytes.count))
                == ["sh", "-c echo hello world"])
    }

    @Test("no padding between the path and the arguments still parses")
    func noPadding() throws {
        let bytes = buffer(count: 1, executablePath: "/bin/ls", padding: 0, arguments: ["ls"])
        #expect(try #require(Libproc.parseArguments(bytes, byteCount: bytes.count)) == ["ls"])
    }

    @Test("a truncated buffer gives back what it can rather than reading past the end")
    func truncated() {
        let bytes = buffer(count: 3, executablePath: "/bin/ls", padding: 1, arguments: ["ls", "-la"])
        let parsed = Libproc.parseArguments(bytes, byteCount: bytes.count)

        #expect(parsed == ["ls", "-la"])
    }

    @Test("a byte count smaller than the buffer is respected")
    func honoursByteCount() {
        let bytes = buffer(count: 2, executablePath: "/bin/ls", padding: 1, arguments: ["ls", "-la"])
        let parsed = Libproc.parseArguments(bytes, byteCount: bytes.count - 2)

        #expect(parsed == ["ls", "-l"])
    }

    @Test("nonsense gives nothing back", arguments: [0, 1, 4])
    func rejectsShortBuffers(length: Int) {
        let bytes = [UInt8](repeating: 0, count: length)
        #expect(Libproc.parseArguments(bytes, byteCount: length) == nil)
    }

    @Test("a zero count gives nothing back")
    func rejectsZeroCount() {
        let bytes = buffer(count: 0, executablePath: "/bin/ls", padding: 1, arguments: [])
        #expect(Libproc.parseArguments(bytes, byteCount: bytes.count) == nil)
    }
}
