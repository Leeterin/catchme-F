import UIKit
import WebKit
import Capacitor

// 앱 안에 직접 만든 플러그인(위젯 연동)은 npm 패키지가 아니라서 자동 등록이 안 됨 - 여기서 직접 등록
class MainViewController: CAPBridgeViewController, WKScriptMessageHandler {
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(CatchmeWidgetPlugin())
        preferKoreanKeyboard()
        webView?.configuration.userContentController.add(self, name: "showEditMenu")
    }

    // 입력칸을 누르면 키보드가 한국어로 먼저 뜨게 함 - 웹 화면에서는 키보드 언어를 고를 수 없어서,
    // 실제로 키보드를 받는 웹뷰 내부 화면(WKContentView)이 "한국어 키보드를 원한다"고 답하게 바꿈.
    // 한국어 키보드가 설치돼 있지 않으면 nil을 돌려줘서 원래대로 기본 키보드가 뜸
    private func preferKoreanKeyboard() {
        guard let cls = NSClassFromString("WKContentView") else { return }
        let sel = #selector(getter: UIResponder.textInputMode)
        guard let method = class_getInstanceMethod(cls, sel) else { return }
        let block: @convention(block) (AnyObject) -> UITextInputMode? = { _ in
            UITextInputMode.activeInputModes.first { ($0.primaryLanguage ?? "").hasPrefix("ko") }
        }
        let imp = imp_implementationWithBlock(block)
        // WKContentView에 직접 없으면 추가(부모 UIResponder는 건드리지 않음), 있으면 그것만 교체
        if !class_addMethod(cls, sel, imp, method_getTypeEncoding(method)) {
            method_setImplementation(method, imp)
        }
    }

    // 웹에서 입력칸을 처음 탭했을 때 붙여넣기 메뉴를 바로 띄움(원래 아이폰은 한 번 더 눌러야 뜸).
    // 좌표는 웹 문서 기준이라 웹뷰 내부 화면(WKContentView) 좌표와 같음. 복사해 둔 글자가 없으면 안 띄움
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "showEditMenu",
              UIPasteboard.general.hasStrings,
              let body = message.body as? [String: Any],
              let x = (body["x"] as? NSNumber)?.doubleValue,
              let y = (body["y"] as? NSNumber)?.doubleValue,
              let scrollView = webView?.scrollView,
              let contentView = scrollView.subviews.first(where: { String(describing: type(of: $0)).hasPrefix("WKContentView") })
        else { return }
        let point = CGPoint(x: x, y: y)
        if #available(iOS 16.0, *) {
            guard let menu = contentView.interactions.compactMap({ $0 as? UIEditMenuInteraction }).first else { return }
            menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: point))
        } else {
            UIMenuController.shared.showMenu(from: contentView, rect: CGRect(origin: point, size: CGSize(width: 1, height: 1)))
        }
    }
}
