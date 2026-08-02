import AthleteCore
import Foundation

struct DashboardEntry: Identifiable, Equatable {
    let id: UUID
    let role: EpistemicRole
    let title: String
    let detail: String
    let artifactID: UUID?
}

struct DashboardState: Equatable {
    let focus: String
    let updatedAt: String
    let coverage: String
    let entries: [DashboardEntry]
    let dataGap: String
}

enum SampleDashboard {
    static let fixture = DashboardState(
        focus: "Сохранить одинаковый отдых между тяжёлыми подходами",
        updatedAt: "обновлено после тренировки",
        coverage: "49 из 61 минуты пригодны для анализа",
        entries: [
            DashboardEntry(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
                role: .computed,
                title: "Отдых увеличился во второй половине",
                detail: "Расчёт по временной шкале подходов. Причина не определена.",
                artifactID: UUID(uuidString: "00000000-0000-0000-0000-000000000032")!
            ),
            DashboardEntry(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000033")!,
                role: .inferred,
                title: "Проверить влияние короткого отдыха",
                detail: "Гипотеза требует ещё двух сопоставимых тренировок.",
                artifactID: nil
            ),
            DashboardEntry(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000034")!,
                role: .userReported,
                title: "Последний подход ощущался как RPE 8",
                detail: "Указано спортсменом в разборе тренировки.",
                artifactID: nil
            ),
        ],
        dataGap: "Для двух подходов не указан внешний вес."
    )
}
