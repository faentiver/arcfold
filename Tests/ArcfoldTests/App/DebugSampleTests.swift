#if DEBUG
@testable import Arcfold
import Testing

/// The samples `DebugRemote` asks a running game for: they take the session's
/// own paths, so that what an acceptance run sees is what a real failure
/// shows.
@MainActor
struct DebugSampleTests {
    @Test func theLongNoticeIsTheNoticeOfAFailedBatterySave() {
        let session = PauseTests.session()
        #expect(session.notice == nil)
        session.show(.longNotice)
        #expect(session.notice == "The save could not be written: The battery save failed: Cannot create battery.sav.tmp")
    }

    @Test func theChipOfAMissingAudioOutputComesAndGoes() {
        let session = PauseTests.session()
        session.show(.audioProblem(shown: true))
        #expect(session.audioProblem == "The audio engine could not start: no output route")
        session.show(.audioProblem(shown: false))
        #expect(session.audioProblem == nil)
    }
}
#endif
