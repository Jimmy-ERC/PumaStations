import Foundation
import Observation
import SwiftData

// MARK: - Employees of the branch

struct EmployeeListItem: Identifiable {
    let employee: UserAccount
    /// Shift of today, if the employee has one.
    let todayShift: WorkShift?
    let weekShiftCount: Int

    var id: PersistentIdentifier { employee.persistentModelID }
}

@Observable
final class EmployeeListViewModel {
    var searchText = ""
    private(set) var items: [EmployeeListItem] = []

    let branch: Branch
    private let store: DataStore

    init(store: DataStore, branch: Branch) {
        self.store = store
        self.branch = branch
    }

    var filteredItems: [EmployeeListItem] {
        let query = searchText.trimmed
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.employee.fullName.localizedCaseInsensitiveContains(query)
                || $0.employee.jobTitle.localizedCaseInsensitiveContains(query)
        }
    }

    var activeCount: Int {
        items.filter { $0.employee.isActive }.count
    }

    var onShiftCount: Int {
        items.filter { $0.todayShift?.isInProgress == true }.count
    }

    func load() {
        let week = PeriodFilter.week.range()
        let shifts = store.workShifts(of: branch)
        items = store.employees(of: branch).map { employee in
            let own = shifts.filter { $0.employee?.persistentModelID == employee.persistentModelID }
            let today = own.filter { $0.isToday }.sorted { $0.shiftRaw < $1.shiftRaw }
            return EmployeeListItem(
                employee: employee,
                todayShift: today.first { $0.isInProgress } ?? today.first,
                weekShiftCount: own.filter { week.contains($0.day) }.count
            )
        }
    }
}

// MARK: - Employee form (create or edit)

@Observable
final class EmployeeFormViewModel {
    /// Positions suggested in the form; any other text is also valid.
    static let suggestedJobTitles = ["Pistero", "Cajero de tienda", "Técnico de mantenimiento"]

    var firstName = ""
    var lastName = ""
    var dui = ""
    var phone = ""
    var jobTitle = EmployeeFormViewModel.suggestedJobTitles[0]
    var email = ""
    var password = ""
    var isActive = true
    var errorMessage: String?

    let branch: Branch
    let editingEmployee: UserAccount?
    private let store: DataStore

    init(store: DataStore, branch: Branch, employee: UserAccount? = nil) {
        self.store = store
        self.branch = branch
        self.editingEmployee = employee
        if let employee {
            firstName = employee.firstName
            lastName = employee.lastName
            dui = employee.dui
            phone = employee.phone
            jobTitle = employee.jobTitle
            email = employee.email
            isActive = employee.isActive
        }
    }

    var isEditing: Bool { editingEmployee != nil }
    var title: String { isEditing ? "Editar empleado" : "Nuevo empleado" }

    func save() -> Bool {
        let normalizedEmail = email.trimmed.lowercased()
        guard !firstName.trimmed.isEmpty, !lastName.trimmed.isEmpty else {
            errorMessage = "Ingresa nombre y apellidos."
            return false
        }
        guard !jobTitle.trimmed.isEmpty else {
            errorMessage = "Ingresa el puesto del empleado."
            return false
        }
        guard normalizedEmail.contains("@"), normalizedEmail.contains(".") else {
            errorMessage = "Ingresa un correo válido."
            return false
        }
        guard !store.isEmailTaken(normalizedEmail, excluding: editingEmployee) else {
            errorMessage = "Ese correo ya está registrado."
            return false
        }
        if !isEditing || !password.isEmpty {
            guard password.count >= 6 else {
                errorMessage = "La contraseña debe tener al menos 6 caracteres."
                return false
            }
        }

        let employee: UserAccount
        if let editingEmployee {
            employee = editingEmployee
            employee.firstName = firstName.trimmed
            employee.lastName = lastName.trimmed
            employee.email = normalizedEmail
        } else {
            employee = UserAccount(
                firstName: firstName.trimmed,
                lastName: lastName.trimmed,
                email: normalizedEmail,
                role: .employee
            )
            store.insert(employee)
            // An employee always belongs to the branch of the manager who creates it.
            employee.branch = branch
        }
        // The password is stored by Supabase Auth, never in the app.
        if !password.isEmpty {
            store.setPassword(password, for: employee)
        }
        employee.dui = dui.trimmed
        employee.phone = phone.trimmed
        employee.jobTitle = jobTitle.trimmed
        employee.isActive = isActive

        do {
            try store.save()
            return true
        } catch {
            errorMessage = "Ocurrió un error al guardar: \(error.localizedDescription)"
            return false
        }
    }
}

// MARK: - Weekly schedule

/// One day of the schedule with the employees of each shift.
struct ScheduleDay: Identifiable {
    let date: Date
    let shifts: [CutShift: [WorkShift]]

    var id: Date { date }

    var isToday: Bool {
        AppCalendar.calendar.isDateInToday(date)
    }

    var isPast: Bool {
        date < AppCalendar.calendar.startOfDay(for: .now)
    }

    func assigned(_ shift: CutShift) -> [WorkShift] {
        shifts[shift] ?? []
    }
}

@Observable
final class ScheduleViewModel {
    private(set) var weekStart: Date
    private(set) var days: [ScheduleDay] = []
    private(set) var employees: [UserAccount] = []
    var errorMessage: String?

    let branch: Branch
    private let store: DataStore

    init(store: DataStore, branch: Branch) {
        self.store = store
        self.branch = branch
        weekStart = ShiftService.weekStart(for: .now)
    }

    var weekLabel: String {
        let end = AppCalendar.calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(AppFormat.date(weekStart, format: "d MMM")) – \(AppFormat.date(end, format: "d MMM"))"
    }

    var isCurrentWeek: Bool {
        weekStart == ShiftService.weekStart(for: .now)
    }

    /// Shifts assigned in the week and hours already worked.
    var assignedCount: Int {
        days.reduce(0) { total, day in total + CutShift.allCases.reduce(0) { $0 + day.assigned($1).count } }
    }

    var workedHours: Double {
        days.reduce(0) { total, day in
            total + CutShift.allCases.reduce(0) { $0 + day.assigned($1).reduce(0) { $0 + $1.workedHours } }
        }
    }

    /// Future shifts of the week nobody covers yet.
    var uncoveredCount: Int {
        days.filter { !$0.isPast }.reduce(0) { total, day in
            total + CutShift.allCases.filter { day.assigned($0).isEmpty }.count
        }
    }

    func load() {
        employees = store.employees(of: branch).filter { $0.isActive }
        let calendar = AppCalendar.calendar
        let shifts = store.workShifts(of: branch)
        days = ShiftService.days(ofWeekStarting: weekStart).map { date in
            let ofDay = shifts.filter { calendar.isDate($0.day, inSameDayAs: date) }
            var byShift: [CutShift: [WorkShift]] = [:]
            for shift in CutShift.allCases {
                byShift[shift] = ofDay
                    .filter { $0.shift == shift }
                    .sorted { ($0.employee?.fullName ?? "") < ($1.employee?.fullName ?? "") }
            }
            return ScheduleDay(date: date, shifts: byShift)
        }
    }

    func moveWeek(by offset: Int) {
        weekStart = AppCalendar.calendar.date(byAdding: .day, value: 7 * offset, to: weekStart) ?? weekStart
        load()
    }

    func goToCurrentWeek() {
        weekStart = ShiftService.weekStart(for: .now)
        load()
    }

    /// Active employees who are not yet in that shift.
    func availableEmployees(for shift: CutShift, on day: ScheduleDay) -> [UserAccount] {
        let assigned = Set(day.assigned(shift).compactMap { $0.employee?.persistentModelID })
        return employees.filter { !assigned.contains($0.persistentModelID) }
    }

    func assign(_ employee: UserAccount, to shift: CutShift, on date: Date) {
        do {
            try ShiftService.assign(employee, to: shift, on: date, in: branch, store: store)
        } catch {
            errorMessage = error.localizedDescription
        }
        load()
    }

    func remove(_ workShift: WorkShift) {
        do {
            try ShiftService.remove(workShift, store: store)
        } catch {
            errorMessage = error.localizedDescription
        }
        load()
    }
}
