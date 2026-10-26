import CoreGraphics
import Foundation

public enum HorizontalDirection: Sendable {
    case left, right
}

public struct GridCell: Equatable {
    public let url: URL
    public let frame: CGRect
    public init(url: URL, frame: CGRect) {
        self.url = url.standardizedFileURL
        self.frame = frame
    }
}

/// The current Finder selection. Multiple selection is kept as URLs so the
/// engine can anchor on the outermost selected item instead of refusing to act.
public enum GridSelection: Equatable {
    case empty
    case multiple([URL])
    case single(URL)
}

public enum WrapDecision: Equatable {
    case native
    case wrap(from: URL, to: URL)
}

/// Visible icon cells clustered into rows by vertical position.
///
/// Deliberately permissive: cells only have to be readable, not fully inside the
/// viewport, and no section/coverage proof is required. Wrapping is a local
/// geometric question: is this cell the last/first of its row, and does the row
/// above/below exist?
public struct GridLayout: Equatable {
    public let cells: [GridCell]
    public let rows: [[GridCell]]

    public init(cells: [GridCell]) {
        let valid = cells.filter { GridLayout.isValid($0.frame) }
        self.cells = valid
        self.rows = GridLayout.cluster(valid)
    }

    static func isValid(_ frame: CGRect) -> Bool {
        [frame.origin.x, frame.origin.y, frame.width, frame.height].allSatisfy(\.isFinite)
            && frame.width > 0 && frame.height > 0
    }

    static func cluster(_ cells: [GridCell]) -> [[GridCell]] {
        let sorted = cells.sorted { lhs, rhs in
            let left = lhs.frame.midY
            let right = rhs.frame.midY
            if abs(left - right) > 1 { return left < right }
            return lhs.frame.minX < rhs.frame.minX
        }
        var rows: [[GridCell]] = []
        var referenceY: CGFloat = 0
        var referenceHeight: CGFloat = 0
        for cell in sorted {
            if !rows.isEmpty {
                let tolerance = max(2, min(cell.frame.height, referenceHeight) * 0.4)
                if abs(cell.frame.midY - referenceY) <= tolerance {
                    rows[rows.count - 1].append(cell)
                    continue
                }
            }
            rows.append([cell])
            referenceY = cell.frame.midY
            referenceHeight = cell.frame.height
        }
        return rows.map { $0.sorted { $0.frame.minX < $1.frame.minX } }
    }

    public func contains(_ url: URL) -> Bool {
        cells.contains { $0.url == url }
    }
}

/// Pure wrap decision. Never touches Finder or input state, so every rule here is
/// covered by unit tests.
///
/// - Right on the last cell of a row moves to the first cell of the next row.
/// - Left on the first cell of a row moves to the last cell of the previous row.
/// - With multiple selected items, the row is anchored on the outermost selected
///   cell in the pressed direction and the write collapses the selection to the
///   target, matching Finder's collapse-on-arrow behaviour.
public struct WrapEngine {
    public init() {}

    public func decide(layout: GridLayout, selection: GridSelection, direction: HorizontalDirection) -> WrapDecision {
        guard !layout.cells.isEmpty, !layout.rows.isEmpty else { return .native }
        guard let anchor = anchorIndex(layout: layout, selection: selection, direction: direction) else { return .native }
        let row = layout.rows[anchor.row]
        let cell = row[anchor.cell]
        guard unique(layout, cell.url) else { return .native }

        switch direction {
        case .right:
            guard anchor.cell == row.count - 1 else { return .native }
            if anchor.row + 1 < layout.rows.count {
                guard let target = layout.rows[anchor.row + 1].first else { return .native }
                guard target.url != cell.url, unique(layout, target.url) else { return .native }
                return .wrap(from: cell.url, to: target.url)
            }
            // Document end: cycle to the top-left cell so continuous presses
            // never dead-end.
            guard let target = layout.rows.first?.first else { return .native }
            guard target.url != cell.url, unique(layout, target.url) else { return .native }
            return .wrap(from: cell.url, to: target.url)
        case .left:
            guard anchor.cell == 0 else { return .native }
            if anchor.row > 0 {
                guard let target = layout.rows[anchor.row - 1].last else { return .native }
                guard target.url != cell.url, unique(layout, target.url) else { return .native }
                return .wrap(from: cell.url, to: target.url)
            }
            guard let target = layout.rows.last?.last else { return .native }
            guard target.url != cell.url, unique(layout, target.url) else { return .native }
            return .wrap(from: cell.url, to: target.url)
        }
    }

    /// Gallery view is a single horizontal strip: the ends cycle instead of
    /// stopping. Only the captured visible strip participates.
    public func cycleWithinRow(layout: GridLayout, selection: GridSelection, direction: HorizontalDirection) -> WrapDecision {
        guard layout.rows.count == 1, let row = layout.rows.first, row.count > 1 else { return .native }
        guard case let .single(url) = selection, let index = row.firstIndex(where: { $0.url == url }) else { return .native }
        let targetIndex: Int
        switch direction {
        case .right:
            guard index == row.count - 1 else { return .native }
            targetIndex = 0
        case .left:
            guard index == 0 else { return .native }
            targetIndex = row.count - 1
        }
        guard row[targetIndex].url != url else { return .native }
        return .wrap(from: row[index].url, to: row[targetIndex].url)
    }

    private func anchorIndex(layout: GridLayout, selection: GridSelection, direction: HorizontalDirection) -> (row: Int, cell: Int)? {
        switch selection {
        case .empty:
            return nil
        case .single(let url):
            return index(layout: layout, url: url)
        case .multiple(let urls):
            let selected = Set(urls.map(\.standardizedFileURL))
            var best: (row: Int, cell: Int)?
            for (rowIndex, row) in layout.rows.enumerated() {
                for (cellIndex, cell) in row.enumerated() where selected.contains(cell.url) {
                    guard let current = best else { best = (rowIndex, cellIndex); continue }
                    let existing = layout.rows[current.row][current.cell]
                    switch direction {
                    case .right where cell.frame.maxX > existing.frame.maxX: best = (rowIndex, cellIndex)
                    case .left where cell.frame.minX < existing.frame.minX: best = (rowIndex, cellIndex)
                    default: break
                    }
                }
            }
            return best
        }
    }

    private func index(layout: GridLayout, url: URL) -> (row: Int, cell: Int)? {
        let target = url.standardizedFileURL
        for (rowIndex, row) in layout.rows.enumerated() {
            if let cellIndex = row.firstIndex(where: { $0.url == target }) {
                return (rowIndex, cellIndex)
            }
        }
        return nil
    }

    private func unique(_ layout: GridLayout, _ url: URL) -> Bool {
        layout.cells.filter { $0.url == url }.count == 1
    }
}

public struct ShiftWrapState: Equatable, Sendable {
    public let anchor: URL
    public let active: URL

    public init(anchor: URL, active: URL) {
        self.anchor = anchor.standardizedFileURL
        self.active = active.standardizedFileURL
    }
}

public enum ShiftWrapDecision: Equatable {
    case native
    case extend([URL], ShiftWrapState)
}

extension GridSelection {
    var selectedURLs: [URL] {
        switch self {
        case .empty: return []
        case .single(let url): return [url.standardizedFileURL]
        case .multiple(let urls): return urls.map(\.standardizedFileURL)
        }
    }
}

extension WrapEngine {
    /// Shift+arrow range extension across row edges.
    ///
    /// Finder keeps the shift anchor internally; this engine only starts a
    /// session when the selection would otherwise stop at the first/last cell of
    /// a row, then moves the active end one cell at a time in row-major order
    /// while the anchor stays put. The returned URLs are the full range to write
    /// into AXSelectedChildren. A selection that is not contiguous in visual
    /// order is left native so Finder can normalize it itself.
    public func shiftDecide(layout: GridLayout,
                            selection: GridSelection,
                            direction: HorizontalDirection,
                            state: ShiftWrapState?) -> ShiftWrapDecision {
        let flat = layout.rows.flatMap { $0 }
        let selected = selection.selectedURLs
        guard !selected.isEmpty else { return .native }
        var indices: [Int] = []
        for url in selected {
            guard let index = flat.firstIndex(where: { $0.url == url }) else { return .native }
            indices.append(index)
        }
        let unique = Set(indices)
        guard unique.count == indices.count,
              let low = unique.min(), let high = unique.max(),
              high - low + 1 == unique.count else { return .native }
        let rows = rowIndices(layout)
        let step = direction == .right ? 1 : -1

        if let state,
           let anchorIndex = flat.firstIndex(where: { $0.url == state.anchor }),
           let activeIndex = flat.firstIndex(where: { $0.url == state.active }),
           min(anchorIndex, activeIndex) == low,
           max(anchorIndex, activeIndex) == high {
            let next = activeIndex + step
            guard flat.indices.contains(next) else { return .native }
            let range = min(anchorIndex, next)...max(anchorIndex, next)
            return .extend(range.map { flat[$0].url },
                           ShiftWrapState(anchor: state.anchor, active: flat[next].url))
        }

        // No session yet: only rescue the press Finder would stop on.
        switch direction {
        case .right:
            guard high + 1 < flat.count, rows[high] != rows[high + 1] else { return .native }
            return .extend((low...high + 1).map { flat[$0].url },
                           ShiftWrapState(anchor: flat[low].url, active: flat[high + 1].url))
        case .left:
            guard low > 0, rows[low] != rows[low - 1] else { return .native }
            return .extend((low - 1...high).map { flat[$0].url },
                           ShiftWrapState(anchor: flat[high].url, active: flat[low - 1].url))
        }
    }

    private func rowIndices(_ layout: GridLayout) -> [Int] {
        var result: [Int] = []
        for (row, cells) in layout.rows.enumerated() {
            result.append(contentsOf: Array(repeating: row, count: cells.count))
        }
        return result
    }
}
