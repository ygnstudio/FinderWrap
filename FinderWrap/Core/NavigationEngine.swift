import Foundation

/// Top-left-origin screen geometry. No Finder access, event injection or UI dependencies.
struct NavigationEngine {
    private struct Row {
        var items: [NavigationItem]
        let centerY: Double
        let height: Double
    }

    func decide(snapshot: LayoutSnapshot, direction: NavigationDirection) -> NavigationDecision {
        guard snapshot.complete, snapshot.mode != .unsupported,
              snapshot.selected.count == 1, let selected = snapshot.selected.first,
              !snapshot.groups.isEmpty,
              Set(snapshot.groups.map(\.id)).count == snapshot.groups.count else { return .passThrough }
        if snapshot.mode != .grouped && snapshot.groups.count != 1 { return .passThrough }

        let allItems = snapshot.groups.flatMap(\.items)
        guard !allItems.isEmpty, Set(allItems.map(\.id)).count == allItems.count,
              allItems.contains(where: { $0.id == selected }),
              allItems.allSatisfy({ valid($0.frame) }) else { return .passThrough }

        let groups = snapshot.groups.sorted { bounds($0.items).minY < bounds($1.items).minY }
        var rows: [Row] = []
        var previousGroupBottom: CGFloat?
        for group in groups {
            guard !group.items.isEmpty else { return .passThrough }
            let box = bounds(group.items)
            if let bottom = previousGroupBottom, box.minY < bottom { return .passThrough }
            previousGroupBottom = box.maxY
            guard let clustered = cluster(group.items) else { return .passThrough }
            rows.append(contentsOf: clustered)
        }
        guard let rowIndex = rows.firstIndex(where: { $0.items.contains(where: { $0.id == selected }) }),
              let itemIndex = rows[rowIndex].items.firstIndex(where: { $0.id == selected }),
              rows[rowIndex].items[itemIndex].fullyVisible else { return .passThrough }

        let target: NavigationItem?
        switch direction {
        case .right:
            if itemIndex + 1 < rows[rowIndex].items.count {
                guard snapshot.mode == .freeArrangement else { return .passThrough }
                target = rows[rowIndex].items[itemIndex + 1]
            } else {
                target = rowIndex + 1 < rows.count ? rows[rowIndex + 1].items.first : nil
            }
        case .left:
            if itemIndex > 0 {
                guard snapshot.mode == .freeArrangement else { return .passThrough }
                target = rows[rowIndex].items[itemIndex - 1]
            } else {
                target = rowIndex > 0 ? rows[rowIndex - 1].items.last : nil
            }
        }
        guard let target, target.fullyVisible else { return .passThrough }
        return .selectTarget(target.id)
    }

    private func valid(_ frame: CGRect) -> Bool {
        [frame.origin.x, frame.origin.y, frame.width, frame.height].allSatisfy(\.isFinite)
            && frame.width > 0 && frame.height > 0
    }

    private func bounds(_ items: [NavigationItem]) -> CGRect {
        items.reduce(CGRect.null) { $0.union($1.frame) }
    }

    private func cluster(_ items: [NavigationItem]) -> [Row]? {
        let ordered = items.sorted {
            $0.frame.midY == $1.frame.midY ? $0.frame.minX < $1.frame.minX : $0.frame.midY < $1.frame.midY
        }
        var rows: [Row] = []
        for item in ordered {
            if let last = rows.last,
               abs(item.frame.midY - last.centerY) <= min(item.frame.height, last.height) * 0.25 {
                rows[rows.count - 1].items.append(item)
            } else {
                rows.append(Row(items: [item], centerY: item.frame.midY, height: item.frame.height))
            }
        }
        var previousBottom: CGFloat?
        for index in rows.indices {
            rows[index].items.sort { $0.frame.minX < $1.frame.minX }
            let box = bounds(rows[index].items)
            if let bottom = previousBottom, box.minY < bottom { return nil }
            previousBottom = box.maxY
            // Overlap and ambiguous near-diagonal placements never create a target.
            for pair in zip(rows[index].items, rows[index].items.dropFirst()) {
                guard pair.0.frame.maxX <= pair.1.frame.minX else { return nil }
            }
        }
        return rows
    }
}
