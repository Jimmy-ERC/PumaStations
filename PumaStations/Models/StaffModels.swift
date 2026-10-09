import Foundation
import SwiftData

// MARK: - Work shift

/// One employee assigned to one of the two shifts of a day, with the attendance marks.
/// The shifts are the same as the sales cuts: morning and evening.
@Model
final class WorkShift {
    /// Id of the row in Supabase.
    var remoteID: UUID = UUID()
    /// Start of the day the shift belongs to.
    var day: Date
    var shiftRaw: Int
    var checkInAt: Date?
    var checkOutAt: Date?

    @Relationship(deleteRule: .nullify)
    var branch: Branch?
    @Relationship(deleteRule: .nullify)
    var employee: UserAccount?

    init(day: Date, shift: CutShift) {
        self.day = AppCalendar.calendar.startOfDay(for: day)
        self.shiftRaw = shift.rawValue
        self.checkInAt = nil
        self.checkOutAt = nil
    }

    var shift: CutShift {
        CutShift(rawValue: shiftRaw) ?? .morning
    }

    var isToday: Bool {
        AppCalendar.calendar.isDateInToday(day)
    }

    /// Checked in and not yet out: the employee can sell.
    var isInProgress: Bool {
        checkInAt != nil && checkOutAt == nil
    }

    func status(now: Date = .now) -> AttendanceStatus {
        if checkOutAt != nil { return .completed }
        if checkInAt != nil { return .inProgress }
        let today = AppCalendar.calendar.startOfDay(for: now)
        return day < today ? .missed : .scheduled
    }

    /// Hours between check-in and check-out (0 while the shift is not completed).
    var workedHours: Double {
        guard let checkInAt, let checkOutAt else { return 0 }
        return max(checkOutAt.timeIntervalSince(checkInAt), 0) / 3_600
    }

    var attendanceText: String {
        guard let checkInAt else { return shift.hoursText }
        let entry = AppFormat.date(checkInAt, format: "h:mm a")
        guard let checkOutAt else { return "Entrada \(entry)" }
        return "\(entry) – \(AppFormat.date(checkOutAt, format: "h:mm a"))"
    }
}
