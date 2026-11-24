import AppKit

/// Writing-column preferences are presentation only. Keep the approved Mac
/// width until the user chooses one of the desktop's narrower columns.
struct MacNoteLayout: Equatable {
    static let widths = [100, 85, 75, 60]
    let width: Int
    let centered: Bool
    init(width: Int = 100, alignment: String = "center") {
        self.width = Self.widths.contains(width) ? width : 100
        centered = alignment != "left"
    }
    func contentWidth(in viewport: CGFloat) -> CGFloat { max(1, (viewport - 92) * CGFloat(width) / 100) }
    func origin(in viewport: CGFloat) -> CGFloat { centered ? max(46, (viewport - contentWidth(in: viewport)) / 2) : 46 }
}
