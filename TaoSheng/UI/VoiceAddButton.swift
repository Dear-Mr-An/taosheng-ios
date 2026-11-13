import SwiftUI
import UIKit

/// 同一加号：轻点打开编辑，长按开始语音；长按识别后取消按钮点击，松手只结束语音。
struct VoiceAddButton: UIViewRepresentable {
    let onTap: () -> Void
    let onHold: () -> Void
    let onRelease: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor(Theme.accent)
        button.layer.cornerRadius = 28
        button.accessibilityLabel = "添加待办"
        button.accessibilityHint = "轻点打字，长按说话，松手结束"
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = 0.45
        hold.allowableMovement = 90
        hold.cancelsTouchesInView = true
        button.addGestureRecognizer(hold)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        context.coordinator.parent = self
        uiView.backgroundColor = UIColor(Theme.accent)
    }

    static func dismantleUIView(_ uiView: UIButton, coordinator: Coordinator) {
        if coordinator.holding { coordinator.parent.onCancel() }
    }

    final class Coordinator: NSObject {
        var parent: VoiceAddButton
        var holding = false

        init(_ parent: VoiceAddButton) { self.parent = parent }

        @objc func tap() {
            guard !holding else { return }
            parent.onTap()
        }

        @objc func hold(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                holding = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                parent.onHold()
            case .ended:
                guard holding else { return }
                holding = false
                parent.onRelease()
            case .cancelled, .failed:
                guard holding else { return }
                holding = false
                parent.onCancel()
            default: break
            }
        }
    }
}
