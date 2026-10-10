import UIKit
import Capacitor

// 앱 안에 직접 만든 플러그인(위젯 연동)은 npm 패키지가 아니라서 자동 등록이 안 됨 - 여기서 직접 등록
class MainViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(CatchmeWidgetPlugin())
        preferKoreanKeyboard()
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
}
