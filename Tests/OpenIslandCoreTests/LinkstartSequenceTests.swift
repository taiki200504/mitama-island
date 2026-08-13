import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Linkstart sequence")
struct LinkstartSequenceTests {
    @Test("It starts in the light, with nothing checked")
    func startsAwakening() {
        #expect(LinkstartSequence.phase(at: 0) == .awakening)
        #expect(LinkstartSequence.phase(at: 1.1) == .awakening)
        #expect(LinkstartSequence.confirmedSenseCount(at: 0.5) == 0)
    }

    /// A clock that jumps backwards must not put the sequence in a state the
    /// view has no drawing for.
    @Test("Time before the beginning is still the beginning")
    func negativeTimeIsAwakening() {
        #expect(LinkstartSequence.phase(at: -5) == .awakening)
    }

    @Test("The senses confirm one at a time, in order")
    func sensesConfirmOneByOne() {
        let start = LinkstartSequence.awakeningDuration
        #expect(LinkstartSequence.phase(at: start + 0.01) == .senses(checked: 0))
        #expect(LinkstartSequence.phase(at: start + 0.6) == .senses(checked: 1))
        #expect(LinkstartSequence.phase(at: start + 1.1) == .senses(checked: 2))
        #expect(LinkstartSequence.phase(at: start + 2.4) == .senses(checked: 4))
    }

    @Test("Language and identity follow the senses, then it ends")
    func laterPhasesFollowInOrder() {
        let sensesEnd = LinkstartSequence.awakeningDuration + LinkstartSequence.sensesDuration
        #expect(LinkstartSequence.phase(at: sensesEnd + 0.1) == .language)

        let languageEnd = sensesEnd + LinkstartSequence.languageDuration
        #expect(LinkstartSequence.phase(at: languageEnd + 0.1) == .identity)

        #expect(LinkstartSequence.phase(at: LinkstartSequence.duration + 0.01) == .complete)
    }

    /// The checklist is on screen the whole way through, so it needs a full
    /// count long after the checks themselves are over.
    @Test("Every sense stays lit once the checks are done")
    func sensesStayLit() {
        let sensesEnd = LinkstartSequence.awakeningDuration + LinkstartSequence.sensesDuration
        #expect(LinkstartSequence.confirmedSenseCount(at: sensesEnd) == LinkstartSequence.senses.count)
        #expect(LinkstartSequence.confirmedSenseCount(at: 60) == LinkstartSequence.senses.count)
    }

    @Test("The count never runs past the list")
    func countIsBounded() {
        for elapsed in stride(from: 0.0, through: LinkstartSequence.duration + 2, by: 0.05) {
            let count = LinkstartSequence.confirmedSenseCount(at: elapsed)
            #expect(count >= 0)
            #expect(count <= LinkstartSequence.senses.count)
        }
    }

    @Test("Every sense carries a distinct string key")
    func senseKeysAreDistinct() {
        let keys = Set(LinkstartSequence.senses.map(\.labelKey))
        #expect(keys.count == LinkstartSequence.senses.count)
    }
}
