import UIKit
import Capacitor

// 앱 안에 직접 만든 플러그인(위젯 연동)은 npm 패키지가 아니라서 자동 등록이 안 됨 - 여기서 직접 등록
class MainViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(CatchmeWidgetPlugin())
    }
}
