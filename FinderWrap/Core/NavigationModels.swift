import Foundation

/// An opaque identity valid only inside its snapshot generation, never a filename.
struct ItemID: Hashable, Codable { let rawValue: String }
struct GroupID: Hashable, Codable { let rawValue: String }

enum NavigationDirection { case left, right }
enum LayoutMode { case ordered, grouped, freeArrangement, unsupported }
enum NavigationDecision: Equatable { case passThrough, selectTarget(ItemID) }

struct NavigationItem {
    let id: ItemID
    let frame: CGRect
    let fullyVisible: Bool
}

struct NavigationGroup {
    let id: GroupID
    /// Geometry and group membership must come from a verified adapter.
    let items: [NavigationItem]
}

struct LayoutSnapshot {
    let generation: UUID
    let mode: LayoutMode
    let groups: [NavigationGroup]
    let selected: Set<ItemID>
    /// False includes stale references, incomplete pagination and uncertain selection.
    let complete: Bool
}
