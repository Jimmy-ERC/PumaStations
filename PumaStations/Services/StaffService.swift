import Foundation
import SwiftData

enum ShiftError: LocalizedError {
    case alreadyAssigned(String)
    case inactiveEmployee
    case pastDay
    case notToday
    case alreadyCheckedIn
    case notCheckedIn
    case alreadyCheckedOut
    case otherShiftInProgress
    case attendanceRecorded

    var errorDescription: String? {
        switch self {
        case .alreadyAssigned(let name):
            return "\(name) ya tiene ese turno asignado."
        case .inactiveEmployee:
            return "No se pueden asignar turnos a un empleado inactivo."
        case .pastDay:
            return "No se pueden asignar turnos en días anteriores."
        case .notToday:
            return "Solo puedes marcar asistencia en el turno de hoy."
        case .alreadyCheckedIn:
            return "Ya marcaste la entrada de este turno."
        case .notCheckedIn:
            return "Primero marca la entrada del turno."
        case .alreadyCheckedOut:
            return "Este turno ya fue completado."
        case .otherShiftInProgress:
            return "Marca la salida de tu otro turno antes de iniciar este."
        case .attendanceRecorded:
            return "No se puede quitar un turno que ya tiene asistencia registrada."
        }
    }
}

/// Rules for work shifts: who can be assigned and how attendance is marked.
enum ShiftService {

    /// Start of the week (Monday) that contains the date.
    static func weekStart(for date: Date) -> Date {
        let calendar = AppCalendar.calendar
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// The 7 days of the week that starts on `weekStart`.
    static func days(ofWeekStarting weekStart: Date) -> [Date] {
        (0..<7).compactMap { AppCalendar.calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    /// Assigns the employee to a shift. An employee has at most one record per day and shift.
    @discardableResult
    static func assign(
        _ employee: UserAccount,
        to shift: CutShift,
        on day: Date,
        in branch: Branch,
        store: DataStore
    ) throws -> WorkShift {
        let calendar = AppCalendar.calendar
        guard employee.isActive else { throw ShiftError.inactiveEmployee }
        guard calendar.startOfDay(for: day) >= calendar.startOfDay(for: .now) else { throw ShiftError.pastDay }
        let taken = store.workShifts(of: employee).contains {
            $0.shift == shift && calendar.isDate($0.day, inSameDayAs: day)
        }
        guard !taken else { throw ShiftError.alreadyAssigned(employee.fullName) }

        let workShift = WorkShift(day: day, shift: shift)
        store.insert(workShift)
        workShift.branch = branch
        workShift.employee = employee
        try store.save()
        return workShift
    }

    /// A shift can be removed only while it has no attendance marks.
    static func remove(_ workShift: WorkShift, store: DataStore) throws {
        guard workShift.checkInAt == nil else { throw ShiftError.attendanceRecorded }
        store.delete(workShift)
        try store.save()
    }

    static func checkIn(_ workShift: WorkShift, store: DataStore, at date: Date = .now) throws {
        guard workShift.isToday else { throw ShiftError.notToday }
        guard workShift.checkInAt == nil else { throw ShiftError.alreadyCheckedIn }
        if let employee = workShift.employee, activeShift(of: employee, store: store) != nil {
            throw ShiftError.otherShiftInProgress
        }
        workShift.checkInAt = date
        try store.save()
    }

    static func checkOut(_ workShift: WorkShift, store: DataStore, at date: Date = .now) throws {
        guard workShift.checkInAt != nil else { throw ShiftError.notCheckedIn }
        guard workShift.checkOutAt == nil else { throw ShiftError.alreadyCheckedOut }
        workShift.checkOutAt = date
        try store.save()
    }

    /// Today's shift where the employee checked in and has not checked out yet.
    static func activeShift(of employee: UserAccount, store: DataStore) -> WorkShift? {
        store.workShifts(of: employee).first { $0.isToday && $0.isInProgress }
    }
}
