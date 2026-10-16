import WidgetKit
import SwiftUI

// 캐치미 홈 화면 위젯 - 다가오는 약속을 크기별로 보여줌
// 소: 오늘부터 7일 일정 / 중: 약속 3개 / 대: 다음 약속 크게 + 4개 더
// 데이터는 앱(웹 화면)이 CatchmeWidgetPlugin으로 App Group에 넣어둔 JSON을 읽음

let appGroup = "group.com.meetzip.app"
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

// 한달 달력 / 오늘 일정 위젯용 - 날짜별 일정 (startMin/endMin은 그날 0시부터 몇 분)
struct CalEvent: Codable, Hashable {
    let title: String
    let startMin: Double
    let endMin: Double
    let kind: String   // avail(예약 가능) / appt(확정 약속) / pending(응답 기다림) / event(일반 일정)
    let color: String?
}

struct CalDay: Codable {
    let key: String    // YYYY-MM-DD
    let events: [CalEvent]
}

struct WidgetPayload: Codable {
    let loggedIn: Bool
    let items: [WidgetItem]
    let days: [CalDay]?   // 예전 버전 앱이 넣어둔 데이터엔 없음
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
    var week: [WeekEvent] = []   // 소 위젯용 - 오늘부터 7일 일정
}

// 일주일 일정 한 줄 (날짜 + 일정)
struct WeekEvent: Hashable {
    let day: Date
    let ev: CalEvent
}

// 오늘부터 7일 동안의 일정 - 예약 가능 시간은 빼고, 오늘 이미 끝난 일정도 뺌
func weekEvents(from payload: WidgetPayload?, now: Date) -> [WeekEvent] {
    let cal = Calendar.current
    var map: [String: [CalEvent]] = [:]
    for d in payload?.days ?? [] { map[d.key] = d.events }
    let today = cal.startOfDay(for: now)
    let nowMin = Double(cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now))
    var out: [WeekEvent] = []
    for i in 0..<7 {
        guard let day = cal.date(byAdding: .day, value: i, to: today) else { continue }
        let evs = (map[dayKey(day)] ?? [])
            .filter { $0.kind != "avail" && (i > 0 || $0.endMin > nowMin) }
            .sorted { $0.startMin < $1.startMin }
        out += evs.map { WeekEvent(day: day, ev: $0) }
    }
    return out
}

struct Provider: TimelineProvider {
    static let sample = [
        WidgetItem(title: "민지", dayMs: Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 * 1000, startMs: nil, endMs: nil, timeLabel: "18:00~21:00", places: "광화문국밥 → 블루보틀"),
        WidgetItem(title: "대학 동기 모임", dayMs: (Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 + 86400 * 3) * 1000, startMs: nil, endMs: nil, timeLabel: "12:00~14:00", places: ""),
    ]

    func placeholder(in context: Context) -> Entry {
        let today = Calendar.current.startOfDay(for: Date())
        return Entry(date: Date(), loggedIn: true, items: Provider.sample, week: [
            WeekEvent(day: today, ev: CalEvent(title: "민지", startMin: 1080, endMin: 1260, kind: "appt", color: nil)),
            WeekEvent(day: today.addingTimeInterval(86400 * 3), ev: CalEvent(title: "대학 동기 모임", startMin: 720, endMin: 840, kind: "event", color: nil)),
        ])
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
        // 오늘 일정이 끝나는 시각마다 (소 위젯 일주일 일정에서 빼려고)
        for ev in payload?.days?.first(where: { $0.key == dayKey(now) })?.events ?? [] {
            let end = cal.startOfDay(for: now).addingTimeInterval(ev.endMin * 60)
            if end > now { moments.append(end) }
        }
        for d in 1...7 {
            if let midnight = cal.date(byAdding: .day, value: d, to: cal.startOfDay(for: now)) { moments.append(midnight) }
        }
        let entries = Array(Set(moments)).sorted().prefix(30).map { makeEntry(at: $0, payload: payload) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    func makeEntry(at date: Date, payload: WidgetPayload?) -> Entry {
        Entry(date: date,
              loggedIn: payload?.loggedIn ?? false,
              items: (payload?.items ?? []).filter { $0.expiresAt > date },
              week: weekEvents(from: payload, now: date))
    }
}

// ---------- 화면 ----------

struct NoAppointmentView: View {
    let loggedIn: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MEETZIP").font(.system(size: 11, weight: .heavy)).foregroundColor(accent)
            Spacer(minLength: 0)
            Text(loggedIn ? "잡힌 약속이 없어요" : "로그인하면\n약속이 보여요")
                .font(.system(size: 15, weight: .bold))
            Text(loggedIn ? "탭해서 약속 잡기" : "탭해서 앱 열기")
                .font(.system(size: 12, weight: .semibold)).foregroundColor(accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// 소: 오늘부터 7일 일정 - 시간순 (3개 + 나머지는 개수)
struct SmallView: View {
    let entry: Entry
    var body: some View {
        let events = entry.week
        let limit = 3
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("일주일").font(.system(size: 15, weight: .heavy)).foregroundColor(accent)
                Spacer()
                if !events.isEmpty {
                    Text("\(events.count)개").font(.system(size: 11, weight: .bold)).foregroundColor(accent)
                }
            }
            if events.isEmpty {
                Spacer(minLength: 0)
                Text(entry.loggedIn ? "7일 안에 일정이 없어요" : "로그인하면\n일정이 보여요").font(.system(size: 14, weight: .bold))
                Text("탭해서 앱 열기").font(.system(size: 11, weight: .semibold)).foregroundColor(accent)
            } else {
                ForEach(Array(events.prefix(limit).enumerated()), id: \.offset) { _, w in
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 2).fill(eventColor(w.ev)).frame(width: 4)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(w.ev.title).font(.system(size: 14, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                            Text("\(dayLabel(w.day, now: entry.date)) \(minLabel(w.ev.startMin))")
                                .font(.system(size: 12, weight: .medium)).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                if events.count > limit {
                    Text("+\(events.count - limit)개 더").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct Row: View {
    let item: WidgetItem
    let now: Date
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(dayLabel(item.day, now: now))
                .font(.system(size: 14, weight: .bold)).foregroundColor(accent)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 17, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                Text([item.timeLabel, item.places.isEmpty ? "장소 미정" : item.places].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 13)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

struct Header: View {
    let count: Int
    var body: some View {
        HStack {
            Text("다가오는 약속").font(.system(size: 14, weight: .heavy))
            Spacer()
            Text("\(count)개").font(.system(size: 12, weight: .bold)).foregroundColor(accent)
        }
    }
}

struct MediumView: View {
    let entry: Entry
    var body: some View {
        if entry.items.isEmpty {
            NoAppointmentView(loggedIn: entry.loggedIn)
        } else {
            VStack(alignment: .leading, spacing: 6) {
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
                        Text(dayLabel(first.day, now: entry.date)).font(.system(size: 15, weight: .bold)).foregroundColor(accent)
                        Spacer()
                        Text(dDayLabel(first.day, now: entry.date)).font(.system(size: 13, weight: .heavy)).foregroundColor(accent)
                    }
                    Text(first.title).font(.system(size: 26, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                    Text([first.timeLabel, first.places.isEmpty ? "장소 미정" : first.places].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 15, weight: .medium)).foregroundColor(.secondary).lineLimit(2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.12)))
                ForEach(entry.items.dropFirst().prefix(4), id: \.self) { Row(item: $0, now: entry.date) }
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
    @ViewBuilder func widgetBackground(_ bg: Color = Color(UIColor.systemBackground)) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            // 기본 여백(16)이 넓어서 일정 칸이 작아짐 - 6씩 줄여 내용을 크게
            padding(-6).containerBackground(bg, for: .widget)
        } else {
            padding(10).background(bg)
        }
    }
}

// ---------- 한달 달력 / 오늘 일정 위젯 ----------

func dayKey(_ date: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

func hexColor(_ hex: String) -> Color? {
    let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
    return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

// 앱 캘린더와 같은 색 (앱이 넘겨준 색이 없으면 종류별 기본색)
func eventColor(_ ev: CalEvent) -> Color {
    if let c = ev.color, let color = hexColor(c) { return color }
    switch ev.kind {
    case "avail": return accent
    case "appt": return Color(red: 0xF4 / 255, green: 0x3F / 255, blue: 0x5E / 255)
    case "pending": return Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255)
    default: return Color(red: 0x8B / 255, green: 0x5C / 255, blue: 0xF6 / 255)
    }
}

// 분 → "18:00" (자정까지인 일정은 "24:00")
func minLabel(_ m: Double) -> String {
    let v = Int(m)
    return String(format: "%02d:%02d", v / 60, v % 60)
}

struct CalEntry: TimelineEntry {
    let date: Date
    let loggedIn: Bool
    let days: [String: [CalEvent]]

    // 앱 화면처럼 지난 날의 예약 가능 시간과 오늘 이미 끝난 예약 가능 시간은 뺌
    func events(on day: Date) -> [CalEvent] {
        let key = dayKey(day)
        let todayKey = dayKey(date)
        let all = days[key] ?? []
        if key < todayKey { return all.filter { $0.kind != "avail" } }
        if key == todayKey {
            let cal = Calendar.current
            let nowMin = Double(cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date))
            return all.filter { $0.kind != "avail" || $0.endMin > nowMin }
        }
        return all
    }
}

struct CalProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalEntry {
        let today = dayKey(Date())
        return CalEntry(date: Date(), loggedIn: true, days: [today: [
            CalEvent(title: "예약 가능", startMin: 600, endMin: 720, kind: "avail", color: nil),
            CalEvent(title: "민지", startMin: 1080, endMin: 1260, kind: "appt", color: nil),
        ]])
    }

    func getSnapshot(in context: Context, completion: @escaping (CalEntry) -> Void) {
        if context.isPreview, loadPayload()?.days == nil {
            completion(placeholder(in: context))
            return
        }
        completion(makeEntry(at: Date(), payload: loadPayload()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalEntry>) -> Void) {
        let now = Date()
        let payload = loadPayload()
        let cal = Calendar.current
        // 오늘 일정이 끝나는 시각마다(끝난 예약 가능 시간 빼기), 그리고 자정마다(오늘 날짜가 바뀌니까) 다시 그림
        var moments: [Date] = [now]
        let startOfToday = cal.startOfDay(for: now)
        for ev in payload?.days?.first(where: { $0.key == dayKey(now) })?.events ?? [] {
            let end = startOfToday.addingTimeInterval(ev.endMin * 60)
            if end > now { moments.append(end) }
        }
        for d in 1...7 {
            if let midnight = cal.date(byAdding: .day, value: d, to: startOfToday) { moments.append(midnight) }
        }
        let entries = Array(Set(moments)).sorted().prefix(30).map { makeEntry(at: $0, payload: payload) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    func makeEntry(at date: Date, payload: WidgetPayload?) -> CalEntry {
        var map: [String: [CalEvent]] = [:]
        for d in payload?.days ?? [] { map[d.key] = d.events }
        return CalEntry(date: date, loggedIn: payload?.loggedIn ?? false, days: map)
    }
}

struct CalLoggedOutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MEETZIP").font(.system(size: 11, weight: .heavy)).foregroundColor(accent)
            Spacer(minLength: 0)
            Text("로그인하면\n일정이 보여요").font(.system(size: 15, weight: .bold))
            Text("탭해서 앱 열기").font(.system(size: 12, weight: .semibold)).foregroundColor(accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// 한달 달력 - 앱 캘린더와 같은 모양 (흰 바탕, 연한 색 칩 + 진한 글씨, 일 빨강·토 파랑, 오늘은 연한 토마토 동그라미)
// 글씨 크기는 칸마다 줄이지 않고 모두 같게 - 길면 칸 끝에서 잘림
let mzInk = Color(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2A / 255)
let mzGray = Color(red: 0x88 / 255, green: 0x87 / 255, blue: 0x80 / 255)
let mzTomato = Color(red: 0xD8 / 255, green: 0x5A / 255, blue: 0x30 / 255)
let mzTomatoLight = Color(red: 0xFA / 255, green: 0xEC / 255, blue: 0xE7 / 255)
let mzDivider = Color(red: 0xF1 / 255, green: 0xEF / 255, blue: 0xE8 / 255)
let mzSun = Color(red: 0xD9 / 255, green: 0x53 / 255, blue: 0x3F / 255)
let mzSat = Color(red: 0x3D / 255, green: 0x7B / 255, blue: 0xD9 / 255)

func eventRGB(_ ev: CalEvent) -> (Double, Double, Double) {
    let fallback: String
    switch ev.kind {
    case "avail": fallback = "#38BDF8"
    case "appt": fallback = "#F43F5E"
    case "pending": fallback = "#F59E0B"
    default: fallback = "#8B5CF6"
    }
    let hex = (ev.color ?? fallback).replacingOccurrences(of: "#", with: "")
    let v = UInt32(hex, radix: 16) ?? 0x8B5CF6
    return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
}

// 앱의 color-mix와 같은 비율 - 배경은 일정 색 28% + 흰색, 글씨는 일정 색 60% + #1E1B18
func pastelBg(_ ev: CalEvent) -> Color {
    let (r, g, b) = eventRGB(ev)
    return Color(red: r * 0.28 + 0.72, green: g * 0.28 + 0.72, blue: b * 0.28 + 0.72)
}
func pastelInk(_ ev: CalEvent) -> Color {
    let (r, g, b) = eventRGB(ev)
    return Color(red: r * 0.6 + 0.4 * 0x1E / 255, green: g * 0.6 + 0.4 * 0x1B / 255, blue: b * 0.6 + 0.4 * 0x18 / 255)
}

struct MonthView: View {
    let entry: CalEntry

    var body: some View {
        let cal = Calendar.current
        let now = entry.date
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let firstWeekday = cal.component(.weekday, from: monthStart) - 1
        let daysInMonth = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let weeks = (firstWeekday + daysInMonth + 6) / 7
        let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

        VStack(spacing: 0) {
            HStack {
                Text("\(cal.component(.year, from: now))년 \(cal.component(.month, from: now))월")
                    .font(.system(size: 13, weight: .heavy)).foregroundColor(mzInk)
                Spacer()
                Text("MEETZIP").font(.system(size: 9, weight: .heavy)).foregroundColor(mzTomato)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 3)
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(weekdays[i]).font(.system(size: 9, weight: .medium))
                        .foregroundColor(i == 0 ? mzSun : (i == 6 ? mzSat : mzGray))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 2)
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: 0) {
                    mzDivider.frame(height: 1)
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { col in
                            let n = w * 7 + col - firstWeekday + 1
                            if n >= 1 && n <= daysInMonth, let day = cal.date(byAdding: .day, value: n - 1, to: monthStart) {
                                MonthCell(n: n, isToday: cal.isDate(day, inSameDayAs: now), col: col, events: entry.events(on: day))
                            } else {
                                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

struct MonthCell: View {
    let n: Int
    let isToday: Bool
    let col: Int
    let events: [CalEvent]

    static let fontSize: CGFloat = 9
    static let numSize: CGFloat = 16
    static let chipH: CGFloat = 12

    var body: some View {
        let busy = events.filter { $0.kind != "avail" }
        let hasAvail = events.contains { $0.kind == "avail" }
        let numColor = isToday ? mzTomato : (col == 0 ? mzSun : (col == 6 ? mzSat : mzInk))
        // 칸 높이에 들어가는 만큼 일정 이름을 넣음 (안 들어가면 색 점)
        GeometryReader { geo in
            let room = Int((geo.size.height - Self.numSize - 2) / (Self.chipH + 1))
            let slots = busy.count > room ? max(room - 1, 0) : room
            VStack(spacing: 1) {
                Text("\(n)")
                    .font(.system(size: 10, weight: isToday ? .heavy : .medium))
                    .foregroundColor(numColor)
                    .frame(width: Self.numSize, height: Self.numSize)
                    .background(Circle().fill(isToday ? mzTomatoLight : Color.clear))
                    .padding(.top, 1)
                if room >= 1 {
                    ForEach(Array(busy.prefix(slots).enumerated()), id: \.offset) { _, ev in
                        Text(ev.title).font(.system(size: Self.fontSize, weight: .semibold)).foregroundColor(pastelInk(ev))
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 3)
                            .frame(maxWidth: .infinity, alignment: .leading).frame(height: Self.chipH)
                            .clipped()
                            .background(RoundedRectangle(cornerRadius: 4).fill(pastelBg(ev)))
                    }
                    if busy.count > slots {
                        Text("+\(busy.count - slots)").font(.system(size: Self.fontSize, weight: .medium)).foregroundColor(mzGray)
                            .frame(height: Self.chipH)
                    } else if hasAvail && busy.count < room {
                        Circle().fill(mzTomato).frame(width: 4, height: 4)
                    }
                } else {
                    // 일정은 색 점, 예약 가능한 날은 토마토 점
                    HStack(spacing: 2) {
                        ForEach(Array(busy.prefix(3).enumerated()), id: \.offset) { _, ev in
                            Circle().fill(pastelInk(ev)).frame(width: 4, height: 4)
                        }
                        if hasAvail && busy.count < 3 { Circle().fill(mzTomato).frame(width: 4, height: 4) }
                    }
                    .frame(height: 4)
                }
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .padding(.horizontal, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

// 오늘 일정 - 시간순 목록 (소 3개 / 중 3개 / 대 7개)
struct TodayView: View {
    @Environment(\.widgetFamily) var family
    let entry: CalEntry

    var body: some View {
        let now = entry.date
        let cal = Calendar.current
        let weekdays = ["일", "월", "화", "수", "목", "금", "토"]
        let events = entry.events(on: now)
        let limit = family == .systemSmall ? 3 : (family == .systemMedium ? 3 : 7)

        VStack(alignment: .leading, spacing: family == .systemSmall ? 5 : 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("오늘").font(.system(size: 15, weight: .heavy)).foregroundColor(accent)
                Text("\(cal.component(.month, from: now))/\(cal.component(.day, from: now)) \(weekdays[cal.component(.weekday, from: now) - 1])")
                    .font(.system(size: 13, weight: .bold)).foregroundColor(.secondary)
                Spacer()
                if family != .systemSmall && !events.isEmpty {
                    Text("\(events.count)개").font(.system(size: 11, weight: .bold)).foregroundColor(accent)
                }
            }
            if events.isEmpty {
                Spacer(minLength: 0)
                Text("오늘 일정이 없어요").font(.system(size: 14, weight: .bold))
                Text("탭해서 일정 보기").font(.system(size: 11, weight: .semibold)).foregroundColor(accent)
            } else {
                ForEach(Array(events.prefix(limit).enumerated()), id: \.offset) { _, ev in
                    TodayRow(ev: ev, compact: family == .systemSmall)
                }
                if events.count > limit {
                    Text("+\(events.count - limit)개 더").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct TodayRow: View {
    let ev: CalEvent
    let compact: Bool
    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2).fill(eventColor(ev)).frame(width: 4)
            VStack(alignment: .leading, spacing: 0) {
                Text(ev.title).font(.system(size: compact ? 14 : 17, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                Text("\(minLabel(ev.startMin))~\(minLabel(ev.endMin))")
                    .font(.system(size: compact ? 12 : 13, weight: .medium)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct CatchmeMonthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CatchmeMonth", provider: CalProvider()) { entry in
            Group {
                if entry.loggedIn { MonthView(entry: entry) } else { CalLoggedOutView() }
            }
            // 앱 캘린더처럼 다크 모드에서도 흰 바탕
            .environment(\.colorScheme, .light)
            .widgetBackground(.white)
        }
        .configurationDisplayName("한달 달력")
        .description("이번 달 일정과 예약 가능한 날을 보여줘요.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct CatchmeTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CatchmeToday", provider: CalProvider()) { entry in
            Group {
                if entry.loggedIn { TodayView(entry: entry) } else { CalLoggedOutView() }
            }.widgetBackground()
        }
        .configurationDisplayName("오늘 일정")
        .description("오늘 일정과 예약 가능 시간을 시간순으로 보여줘요.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct CatchmeWidgets: WidgetBundle {
    // 위젯 고르는 화면은 이 순서대로 넘어가서, 달력을 맨 앞에 둠 (약속 위젯이 먼저 나오면 달력이 없는 줄 앎)
    var body: some Widget {
        CatchmeMonthWidget()
        CatchmeTodayWidget()
        CatchmeWidget()
    }
}

struct CatchmeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CatchmeUpcoming", provider: Provider()) { entry in
            CatchmeWidgetView(entry: entry).widgetBackground()
        }
        .configurationDisplayName("다가오는 약속")
        .description("작은 크기는 일주일 일정, 중간·큰 크기는 확정된 약속을 보여줘요.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
