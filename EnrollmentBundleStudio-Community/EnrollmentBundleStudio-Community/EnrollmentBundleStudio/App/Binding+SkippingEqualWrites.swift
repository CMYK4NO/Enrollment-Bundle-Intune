import SwiftUI

extension Binding where Value: Equatable {
    /// A binding that ignores writes of an unchanged value.
    ///
    /// Text editors and pickers sometimes write the current value back during layout. Through a document
    /// binding that would publish a change inside a view update (SwiftUI warns about this) and mark the
    /// document as edited although nothing changed.
    func skippingEqualWrites() -> Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { newValue, transaction in
                guard newValue != wrappedValue else { return }
                self.transaction(transaction).wrappedValue = newValue
            }
        )
    }
}

extension Binding {
    /// A binding that applies writes on the next main run-loop turn.
    ///
    /// For menu-based controls only (popup and segmented pickers, toggles and pickers inside menus, the color
    /// well): on macOS 26 AppKit can deliver their selection while SwiftUI is updating views, and writing to
    /// the document or the view model at that moment triggers "Publishing changes from within view updates".
    /// Never use this for text fields: delayed writes would make the insertion point jump while typing.
    func deferringWrites() -> Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { newValue in
                DispatchQueue.main.async {
                    self.wrappedValue = newValue
                }
            }
        )
    }
}
