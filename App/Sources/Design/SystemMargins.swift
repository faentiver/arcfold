import SwiftUI
import UIKit

/// The margins the system keeps for content inside the safe area: where the
/// large title of a navigation bar begins and where a list puts its rows.
/// They differ per side and per pose. On the Duo they measure 20 pt, but 0
/// on a side that already has an inset: beside the bar of the outer display
/// the content ends at the bar, and sideways it begins at the inset.
nonisolated struct SystemMargins: Sendable, Hashable {
    var leading: CGFloat
    var trailing: CGFloat

    /// For previews and fixed pages that have no window to ask.
    static let standard = SystemMargins(leading: 20, trailing: 20)
}

/// Reports `UIViewController.systemMinimumLayoutMargins` of the controller
/// that hosts this view, when the view appears and whenever they change.
/// SwiftUI has no value for them: `scenePadding` measures 16 pt on every
/// side in every pose of the Duo, the large title begins at 20 or at the
/// inset. Put it behind the view whose content follows the margins.
struct SystemMarginsReader: UIViewRepresentable {
    let action: (SystemMargins) -> Void

    func makeUIView(context: Context) -> MarginsView {
        let view = MarginsView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: MarginsView, context: Context) {
        view.action = action
        // The margins can change without the frame of this view.
        view.setNeedsLayout()
    }

    final class MarginsView: UIView {
        var action: ((SystemMargins) -> Void)?
        private var reported: SystemMargins?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            setNeedsLayout()
        }

        private func report() {
            guard window != nil, let controller = sequence(first: self as UIResponder, next: \.next)
                .lazy.compactMap({ $0 as? UIViewController }).first else { return }
            let minimum = controller.systemMinimumLayoutMargins
            let margins = SystemMargins(leading: minimum.leading, trailing: minimum.trailing)
            guard margins != reported else { return }
            reported = margins
            // After the layout pass: the action changes the state of a view.
            Task { [weak self] in
                self?.action?(margins)
            }
        }
    }
}
