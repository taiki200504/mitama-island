import Testing
@testable import OpenIslandApp

struct TravelBluetoothNameTests {
    @Test func recognizesTheObservedOpenComm2Name() {
        #expect(TravelBluetooth.matchesName("OpenComm2 by Shokz_II"))
        #expect(TravelBluetooth.matchesName("OpenComm2 by Shokz"))
    }
    @Test func otherBluetoothDevicesAreNotSelectedByName() {
        for name in ["Magic Keyboard", "OpenRun by Shokz", "OpenComm", "Unknown OpenComm2 Speaker", ""] {
            #expect(!TravelBluetooth.matchesName(name))
        }
    }
}
