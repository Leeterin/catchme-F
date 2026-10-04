import WidgetKit
import SwiftUI

// 캐치미 홈 화면 위젯 - 다가오는 약속을 크기별로 보여줌
// 소: 바로 다음 약속 1개 / 중: 3개 / 대: 다음 약속 크게 + 5개 더
// 데이터는 앱(웹 화면)이 CatchmeWidgetPlugin으로 App Group에 넣어둔 JSON을 읽음

let appGroup = "group.com.catchme.app"
let accent = Color(red: 0x38 / 255, green: 0xBD / 255, blue: 0xF8 / 255)

struct WidgetItem: Codable, Hashable {
    let title: String
    let dayMs: Double
    let startMs: Double?
    let endMs: Double?
    let timeLabel: String
    let places: String

    var day: Date { Date(timeIntervalSince1970: dayMs / 1000) }
    // 끝나는 시각이 지나면 위젯에서 뺌 (시간이 없으면 그날 자정까지 보여줌)
    var expiresAt: Date {
        if let endMs = endMs { return Date(timeIntervalSince1970: endMs / 1000) }
        return Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
    }
}

struct WidgetPayload: Codable {
    let loggedIn: Bool
    let items: [WidgetItem]
}

func loadPayload() -> WidgetPayload? {
    guard let json = UserDefaults(suiteName: appGroup)?.string(forKey: "widgetData"),
          let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(WidgetPayload.self, from: data)
}

// 오늘 / 내일 / 금요일 / 10/12 - 웹 홈 화면과 같은 규칙
func dayLabel(_ day: Date, now: Date) -> String {
    let cal = Calendar.current
    let diff = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: day)).day ?? 0
    if diff == 0 { return "오늘" }
    if diff == 1 { return "내일" }
    let weekdays = ["일", "월", "화", "수", "목", "금", "토"]
    if diff > 1 && diff < 7 { return weekdays[cal.component(.weekday, from: day) - 1] + "요일" }
    return "\(cal.component(.month, from: day))/\(cal.component(.day, from: day))"
}

func dDayLabel(_ day: Date, now: Date) -> String {
    let cal = Calendar.current
    let diff = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: day)).day ?? 0
    return diff <= 0 ? "D-DAY" : "D-\(diff)"
}

struct Entry: TimelineEntry {
    let date: Date
    let loggedIn: Bool
    let items: [WidgetItem]
}

struct Provider: TimelineProvider {
    static let sample = [
        WidgetItem(title: "민지", dayMs: Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 * 1000, startMs: nil, endMs: nil, timeLabel: "18:00~21:00", places: "광화문국밥 → 블루보틀"),
        WidgetItem(title: "대학 동기 모임", dayMs: (Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 + 86400 * 3) * 1000, startMs: nil, endMs: nil, timeLabel: "12:00~14:00", places: ""),
    ]

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), loggedIn: true, items: Provider.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        if context.isPreview, loadPayload() == nil {
            completion(placeholder(in: context))
            return
        }
        completion(makeEntry(at: Date(), payload: loadPayload()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let now = Date()
        let payload = loadPayload()
        // 약속이 끝나는 시각마다, 그리고 자정마다(오늘→내일 라벨이 바뀌니까) 다시 그림
        let cal = Calendar.current
        var moments: [Date] = [now]
        for item in payload?.items ?? [] where item.expiresAt > now { moments.append(item.expiresAt) }
        for d in 1...7 {
            if let midnight = cal.date(byAdding: .day, value: d, to: cal.startOfDay(for: now)) { moments.append(midnight) }
        }
        let entries = Array(Set(moments)).sorted().prefix(30).map { makeEntry(at: $0, payload: payload) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    func makeEntry(at date: Date, payload: WidgetPayload?) -> Entry {
        Entry(date: date,
              loggedIn: payload?.loggedIn ?? false,
              items: (payload?.items ?? []).filter { $0.expiresAt > date })
    }
}

// ---------- 화면 ----------

struct NoAppointmentView: View {
    let loggedIn: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CATCHME").font(.system(size: 11, weight: .heavy)).foregroundColor(accent)
            Spacer(minLength: 0)
            Text(loggedIn ? "잡힌 약속이 없어요" : "로그인하면\n약속이 보여요")
                .font(.system(size: 15, weight: .bold))
            Text(loggedIn ? "탭해서 약속 잡기" : "탭해서 앱 열기")
                .font(.system(size: 12, weight: .semibold)).foregroundColor(accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct SmallView: View {
    let entry: Entry
    var body: some View {
        if let item = entry.items.first {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("다음 약속").font(.system(size: 11, weight: .bold)).foregroundColor(.secondary)
                    Spacer()
                    Text(dDayLabel(item.day, now: entry.date))
                        .font(.system(size: 10, weight: .heavy)).foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(accent))
                }
                Spacer(minLength: 0)
                Text(dayLabel(item.day, now: entry.date)).font(.system(size: 13, weight: .bold)).foregroundColor(accent)
                Text(item.title).font(.system(size: 18, weight: .heavy)).lineLimit(1)
                if !item.timeLabel.isEmpty {
                    Text(item.timeLabel).font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary).lineLimit(1)
                }
                Text(item.places.isEmpty ? "장소 미정" : item.places)
                    .font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            NoAppointmentView(loggedIn: entry.loggedIn)
        }
    }
}

struct Row: View {
    let item: WidgetItem
    let now: Date
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(dayLabel(item.day, now: now))
                .font(.system(size: 12, weight: .bold)).foregroundColor(accent)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 14, weight: .bold)).lineLimit(1)
                Text([item.timeLabel, item.places.isEmpty ? "장소 미정" : item.places].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

struct Header: View {
    let count: Int
    var body: some View {
        HStack {
            Text("다가오는 약속").font(.system(size: 13, weight: .heavy))
            Spacer()
            Text("\(count)개").font(.system(size: 11, weight: .bold)).foregroundColor(accent)
        }
    }
}

struct MediumView: View {
    let entry: Entry
    var body: some View {
        if entry.items.isEmpty {
            NoAppointmentView(loggedIn: entry.loggedIn)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                Header(count: entry.items.count)
                ForEach(entry.items.prefix(3), id: \.self) { Row(item: $0, now: entry.date) }
                Spacer(minLength: 0)
            }
        }
    }
}

struct LargeView: View {
    let entry: Entry
    var body: some View {
        if let first = entry.items.first {
            VStack(alignment: .leading, spacing: 10) {
                Header(count: entry.items.count)
                // 바로 다음 약속은 크게
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(dayLabel(first.day, now: entry.date)).font(.system(size: 13, weight: .bold)).foregroundColor(accent)
                        Spacer()
                        Text(dDayLabel(first.day, now: entry.date)).font(.system(size: 11, weight: .heavy)).foregroundColor(accent)
                    }
                    Text(first.title).font(.system(size: 20, weight: .heavy)).lineLimit(1)
                    Text([first.timeLabel, first.places.isEmpty ? "장소 미정" : first.places].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 12, weight: .medium)).foregroundColor(.secondary).lineLimit(2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.12)))
                ForEach(entry.items.dropFirst().prefix(5), id: \.self) { Row(item: $0, now: entry.date) }
                Spacer(minLength: 0)
            }
        } else {
            NoAppointmentView(loggedIn: entry.loggedIn)
        }
    }
}

struct CatchmeWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry
    var body: some View {
        switch family {
        case .systemSmall: SmallView(entry: entry)
        case .systemMedium: MediumView(entry: entry)
        default: LargeView(entry: entry)
        }
    }
}

extension View {
    // iOS 17부터는 위젯 배경을 containerBackground로 지정해야 함
    @ViewBuilder func widgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(Color(UIColor.systemBackground), for: .widget)
        } else {
            padding().background(Color(UIColor.systemBackground))
        }
    }
}

@main
struct CatchmeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CatchmeUpcoming", provider: Provider()) { entry in
            CatchmeWidgetView(entry: entry).widgetBackground()
        }
        .configurationDisplayName("다가오는 약속")
        .description("확정된 약속을 날짜순으로 보여줘요.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
