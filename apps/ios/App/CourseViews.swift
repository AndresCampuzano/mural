import SwiftUI
import MuralCore

/// The entry to a module's textbook course, shown on the Themes tab only when the module has one.
struct CourseCard: View {
    let course: Course
    let language: LanguageModule
    let choose: (ConversationTheme) -> Void
    var body: some View {
        NavigationLink { CourseView(course: course, language: language, choose: choose) } label: {
            HStack(spacing: 16) {
                Image(systemName: "books.vertical").font(.system(size: 26, weight: .light)).foregroundStyle(MuralColor.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your course").font(.system(.caption, design: .rounded, weight: .medium)).foregroundStyle(MuralColor.secondary)
                    Text(course.title).font(.system(.headline, design: .rounded)).multilineTextAlignment(.leading)
                    Text(course.detail).font(.caption).foregroundStyle(MuralColor.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(MuralColor.secondary)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(MuralColor.butter.opacity(0.7), in: RoundedRectangle(cornerRadius: 26))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("course-card")
    }
}

struct CourseView: View {
    let course: Course
    let language: LanguageModule
    let choose: (ConversationTheme) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "Your course", title: course.title, subtitle: "Pick the unit you’re studying. Topics that draw on more than one unit appear in each.")
                ForEach(course.books, id: \.self) { book in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(book).font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(MuralColor.secondary)
                        ForEach(course.units(in: book)) { unit in
                            NavigationLink { CourseUnitView(course: course, unit: unit, language: language, choose: choose) } label: {
                                HStack(spacing: 14) {
                                    Text("\(unit.number)").font(.system(.title3, design: .rounded, weight: .semibold)).frame(width: 34)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(unit.title).font(.system(.headline, design: .rounded))
                                        Text(unit.meaning).font(.caption).foregroundStyle(MuralColor.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Text("\(course.topics(in: unit).count) topics").font(.caption2).foregroundStyle(MuralColor.secondary)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(MuralColor.secondary)
                                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(MuralColor.panels[unit.number % 4], in: RoundedRectangle(cornerRadius: 22))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("course-unit-\(unit.number)")
                        }
                    }
                }
            }.padding(24)
        }.foregroundStyle(MuralColor.ink).background(MuralColor.cream)
    }
}

struct CourseUnitView: View {
    let course: Course
    let unit: CourseUnit
    let language: LanguageModule
    let choose: (ConversationTheme) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeading(eyebrow: "Unit \(unit.number) · \(unit.book)", title: unit.title, subtitle: unit.meaning)
                chips("Vocabulary", unit.vocabulary)
                chips("Grammar", unit.grammar)
                ForEach(course.topics(in: unit)) { topic in topicCard(topic) }
                topicCard(course.review(of: unit), modes: [.drill])
                Text("Practice here counts like any conversation: words earn recall bars only when you use them yourself.")
                    .font(.footnote).foregroundStyle(MuralColor.secondary)
            }.padding(24)
        }.foregroundStyle(MuralColor.ink).background(MuralColor.cream)
    }
    private func chips(_ label: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased()).font(.system(.caption2, design: .rounded, weight: .medium)).tracking(1.2).foregroundStyle(MuralColor.secondary)
            FlowLayout(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text(item).font(.caption).padding(.horizontal, 12).padding(.vertical, 8).background(.white.opacity(0.7), in: Capsule())
                }
            }
        }
    }
    private func topicCard(_ topic: CourseTopic, modes: [PracticeMode] = PracticeMode.allCases) -> some View {
        let others = course.units(for: topic).filter { $0.id != unit.id }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: topic.symbol).font(.system(size: 24, weight: .light)).foregroundStyle(MuralColor.secondary).frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(topic.title).font(.system(.headline, design: .rounded))
                    Text(topic.subtitle).font(.caption).foregroundStyle(MuralColor.secondary)
                    if !others.isEmpty {
                        Text("Also in " + others.map { "unit \($0.number)" }.joined(separator: ", "))
                            .font(.caption2).foregroundStyle(MuralColor.secondary)
                    }
                }
            }
            HStack(spacing: 10) {
                ForEach(modes, id: \.self) { mode in
                    Button { choose(course.theme(for: topic, mode: mode, language: language)) } label: {
                        Label(mode.title, systemImage: mode.symbol).font(.subheadline).lineLimit(1).minimumScaleFactor(0.8)
                            .padding(.horizontal, 14).padding(.vertical, 11).frame(maxWidth: .infinity)
                            .background(mode == .conversation ? MuralColor.peach : .white.opacity(0.75), in: Capsule())
                            .contentShape(Capsule())
                    }.buttonStyle(.plain).accessibilityIdentifier("course-\(topic.id)-\(mode.rawValue)")
                }
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(MuralColor.panels[unit.number % 4], in: RoundedRectangle(cornerRadius: 24))
    }
}

/// Wraps short labels onto as many lines as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        rows(proposal.width ?? .infinity, subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, point) in rows(bounds.width, subviews).points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }
    private func rows(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = []; var x: CGFloat = 0; var y: CGFloat = 0; var rowHeight: CGFloat = 0; var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height); widest = max(widest, x - spacing)
        }
        return (points, CGSize(width: widest, height: y + rowHeight))
    }
}
