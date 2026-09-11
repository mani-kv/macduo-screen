import Testing
@testable import LidSensor

struct LidReportTests {
    @Test func decodesLittleEndianDegrees() {
        #expect(LidReport.decode([1, 132, 0]) == 132)
        #expect(LidReport.decode([1, 104, 1]) == 360)
        #expect(LidReport.decode([1, 0, 0]) == 0)
    }

    @Test func rejectsMalformedOrInvalidReports() {
        #expect(LidReport.decode([]) == nil)
        #expect(LidReport.decode([1, 90]) == nil)
        #expect(LidReport.decode([2, 90, 0]) == nil)
        #expect(LidReport.decode([1, 105, 1]) == nil)
        #expect(LidReport.decode([1, 255, 255]) == nil)
    }
}
