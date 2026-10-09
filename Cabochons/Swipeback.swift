// MARK: - SwipeBack
// Restores the edge swipe-back gesture on screens with a hidden navigation
// bar. The wordmark header hides the bar on iPhone, and UIKit's default
// gatekeeper for the gesture refuses to start without one. This makes every
// navigation controller its own gatekeeper: the swipe is allowed whenever
// there's a screen to go back to and no push or pop is already animating.
//
// APP TARGET ONLY, iOS only. Do not add to CabochonsWidget.

#if os(iOS)
// public, unlike the rest of the app: a conformance on a UIKit class is as
// public as the class, so the compiler needs UIKit's types visible at that
// level. Harmless in an app target, where nothing outside sees the module.
public import UIKit

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // On the root screen there's nothing to pop to; starting the gesture
        // there freezes the stack. Same if it starts mid-transition.
        viewControllers.count > 1 && transitionCoordinator == nil
    }
}
#endif
