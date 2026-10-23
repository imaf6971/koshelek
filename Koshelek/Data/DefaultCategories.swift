import Foundation
import SwiftData

enum DefaultCategories {
    private struct Spec {
        var name: String, icon: String, color: String
        var subs: [(String, String)] = []
    }

    private static let expense: [Spec] = [
        Spec(name: "Еда", icon: "fork.knife", color: "clay", subs: [("Продукты", "cart"), ("Кафе и рестораны", "cup.and.saucer"), ("Доставка еды", "bag")]),
        Spec(name: "Транспорт", icon: "bus", color: "slate", subs: [("Такси", "car"), ("Общественный транспорт", "tram"), ("Топливо", "fuelpump")]),
        Spec(name: "Жильё", icon: "house", color: "olive", subs: [("Аренда", "house"), ("Коммунальные услуги", "bolt"), ("Интернет и связь", "wifi")]),
        Spec(name: "Здоровье", icon: "cross.case", color: "rose"),
        Spec(name: "Одежда", icon: "tshirt", color: "plum"),
        Spec(name: "Развлечения", icon: "film", color: "ochre", subs: [("Кино и театр", "film"), ("Подписки", "play.rectangle")]),
        Spec(name: "Образование", icon: "book", color: "teal"),
        Spec(name: "Подарки", icon: "gift", color: "brick"),
        Spec(name: "Путешествия", icon: "airplane", color: "sage"),
        Spec(name: "Дом и быт", icon: "sofa", color: "sand"),
        Spec(name: "Красота", icon: "sparkles", color: "rose"),
        Spec(name: "Питомцы", icon: "pawprint", color: "stone"),
        Spec(name: "Прочее", icon: "ellipsis.circle", color: "stone"),
    ]

    private static let income: [Spec] = [
        Spec(name: "Зарплата", icon: "banknote", color: "moss"),
        Spec(name: "Подработка", icon: "briefcase", color: "olive"),
        Spec(name: "Проценты", icon: "percent", color: "teal"),
        Spec(name: "Подарки", icon: "gift", color: "sage"),
        Spec(name: "Возвраты", icon: "arrow.uturn.backward", color: "slate"),
        Spec(name: "Прочие доходы", icon: "ellipsis.circle", color: "stone"),
    ]

    /// Creates the default Russian category set when no categories exist.
    static func ensure(in context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Category>())) ?? 0
        guard count == 0 else { return }
        for (kind, specs) in [(CategoryKind.expense, expense), (.income, income)] {
            for (i, s) in specs.enumerated() {
                let parent = Category(name: s.name, icon: s.icon, colorKey: s.color, kind: kind, sortOrder: i)
                context.insert(parent)
                for (j, sub) in s.subs.enumerated() {
                    context.insert(Category(name: sub.0, icon: sub.1, colorKey: s.color, kind: kind, sortOrder: j, parent: parent))
                }
            }
        }
        context.saveOrReport()
    }
}
