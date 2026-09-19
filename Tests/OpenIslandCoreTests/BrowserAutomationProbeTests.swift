import Testing
@testable import OpenIslandCore

struct BrowserAutomationProbeTests {
    @Test("No lsof output returns false")
    func noOutput() {
        #expect(BrowserAutomationProbe.isDriven(lsofOutput: "", browserPID: 1234) == false)
    }

    @Test("Only browser's listen line returns false")
    func onlyBrowserListen() {
        let output = """
        COMMAND    PID   USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        mitama   1234 taiki    5u  IPv4  0x123    0t0  TCP 127.0.0.1:9222 (LISTEN)
        """
        #expect(BrowserAutomationProbe.isDriven(lsofOutput: output, browserPID: 1234) == false)
    }

    @Test("One external client connection returns true")
    func oneClient() {
        let output = """
        COMMAND    PID   USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        mitama   1234 taiki    5u  IPv4  0x123    0t0  TCP 127.0.0.1:9222 (LISTEN)
        python   5678 taiki    3u  IPv4  0x456    0t0  TCP 127.0.0.1:9222->127.0.0.1:12345 (ESTABLISHED)
        """
        #expect(BrowserAutomationProbe.isDriven(lsofOutput: output, browserPID: 1234) == true)
    }

    @Test("Multiple client connections returns true")
    func multipleClients() {
        let output = """
        COMMAND    PID   USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        mitama   1234 taiki    5u  IPv4  0x123    0t0  TCP 127.0.0.1:9222 (LISTEN)
        python   5678 taiki    3u  IPv4  0x456    0t0  TCP 127.0.0.1:9222->127.0.0.1:12345 (ESTABLISHED)
        node     8901 taiki    4u  IPv4  0x789    0t0  TCP 127.0.0.1:9222->127.0.0.1:12346 (ESTABLISHED)
        """
        #expect(BrowserAutomationProbe.isDriven(lsofOutput: output, browserPID: 1234) == true)
    }

    @Test("Browser's own connection is excluded")
    func browserOwnConnection() {
        // When browser itself tries to connect to its own port
        let output = """
        COMMAND    PID   USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        mitama   1234 taiki    5u  IPv4  0x123    0t0  TCP 127.0.0.1:9222 (LISTEN)
        mitama   1234 taiki    6u  IPv4  0x124    0t0  TCP 127.0.0.1:9222->127.0.0.1:12345 (ESTABLISHED)
        """
        #expect(BrowserAutomationProbe.isDriven(lsofOutput: output, browserPID: 1234) == false)
    }

    @Test("Malformed lines are skipped")
    func malformedLines() {
        let output = """
        garbage data that's not lsof output
        mitama   1234 taiki    5u  IPv4  0x123    0t0  TCP 127.0.0.1:9222 (LISTEN)
        python   5678
        python   5678 taiki    3u  IPv4  0x456    0t0  TCP 127.0.0.1:9222->127.0.0.1:12345 (ESTABLISHED)
        """
        #expect(BrowserAutomationProbe.isDriven(lsofOutput: output, browserPID: 1234) == true)
    }
}
