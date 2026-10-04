import Foundation
import Capacitor
import WidgetKit

// 웹 화면이 넘겨준 "다가오는 약속" 목록을 App Group 저장소에 넣고 홈 화면 위젯을 새로 그리게 함
// (위젯은 앱과 따로 실행돼서 App Group으로만 데이터를 나눠 가질 수 있음)
@objc(CatchmeWidgetPlugin)
public class CatchmeWidgetPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "CatchmeWidgetPlugin"
    public let jsName = "CatchmeWidget"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "update", returnType: CAPPluginReturnPromise)
    ]

    static let appGroup = "group.com.catchme.app"
    static let dataKey = "widgetData"

    @objc func update(_ call: CAPPluginCall) {
        guard let data = call.getString("data") else {
            call.reject("data가 없어요")
            return
        }
        UserDefaults(suiteName: CatchmeWidgetPlugin.appGroup)?.set(data, forKey: CatchmeWidgetPlugin.dataKey)
        WidgetCenter.shared.reloadAllTimelines()
        call.resolve()
    }
}
