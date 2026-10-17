import UIKit
import Capacitor
import UserNotifications

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = MainViewController()
        window?.makeKeyAndVisible()

        SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)

        // 앱이 꺼져 있을 때 알림을 눌러 켜지면, 그 탭 정보는 여기(connectionOptions)로만 들어옴 -
        // 알림 처리기가 아직 안 붙어 있던 시점이라 그냥 두면 사라져서 채팅방으로 안 가고 첫 화면만 뜸. 직접 넘겨줌
        if let response = connectionOptions.notificationResponse,
           let vc = window?.rootViewController as? CAPBridgeViewController {
            vc.loadViewIfNeeded()
            vc.bridge?.notificationRouter.userNotificationCenter(UNUserNotificationCenter.current(), didReceive: response) {}
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        SceneDelegateProxy.shared.scene(scene, continue: userActivity)
    }
}
