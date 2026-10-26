import Foundation

public enum HorizontalDirection: Sendable { case left, right }

/// File identities stay in memory. Diagnostics must only export counts/reasons.
public struct VisibleItem: Equatable {
    public let url: URL
    public let frame: CGRect
    public init(url: URL, frame: CGRect) { self.url = url.standardizedFileURL; self.frame = frame }
}

public struct VisibleSection {
    public let items: [VisibleItem]
    /// Unreadable nodes with known geometry invalidate only this part of a section.
    public let gaps: [CGRect]
    /// A node whose bounds cannot be read prevents establishing local coverage.
    public let coverageKnown: Bool
    /// Both ends must be proven before traversing a section boundary. In
    /// particular, folded groups must not skip their unexposed items.
    public let startsAtFirstItem: Bool
    public let endsAtLastItem: Bool
    public init(items: [VisibleItem], gaps: [CGRect] = [], coverageKnown: Bool = true,
                startsAtFirstItem: Bool = false, endsAtLastItem: Bool = false) {
        self.items = items; self.gaps = gaps; self.coverageKnown = coverageKnown
        self.startsAtFirstItem = startsAtFirstItem; self.endsAtLastItem = endsAtLastItem
    }
}

public struct VisibleLayout {
    /// Sections retain their presentation order, including unreadable sections.
    public let sections: [VisibleSection]
    public let viewport: CGRect
    public let coversFullWidth: Bool
    public init(sections: [VisibleSection], viewport: CGRect, coversFullWidth: Bool) {
        self.sections = sections; self.viewport = viewport; self.coversFullWidth = coversFullWidth
    }
}

public enum LocalDecision: Equatable {
    case native
    case wrap(from: URL, to: URL)
}

/// Only visible neighboring rows participate. A failure in a distant section
/// cannot disable a valid boundary. This engine never accesses Finder or input.
public struct LocalNavigation {
    private struct Row {
        var items: [VisibleItem]
        var valid = true
        var bounds: CGRect { items.reduce(.null) { $0.union($1.frame) } }
    }

    public init() {}

    public func decide(layout: VisibleLayout, selection: FinderSelectionReader.Selection,
                       direction: HorizontalDirection) -> LocalDecision {
        guard layout.coversFullWidth, valid(layout.viewport), case let .single(selected) = selection else { return .native }
        let matches = layout.sections.enumerated().flatMap { index, section in
            section.items.filter { $0.url == selected }.map { (index, $0) }
        }
        guard matches.count == 1, let (sectionIndex, source) = matches.first else { return .native }
        let section = layout.sections[sectionIndex]
        guard section.coverageKnown, let rows = makeRows(section.items),
              let rowIndex = rows.firstIndex(where: { $0.items.contains(source) }),
              let itemIndex = rows[rowIndex].items.firstIndex(of: source),
              fullRow(rows[rowIndex], in: layout.viewport) else { return .native }
        let targetRow: Row
        let destinationSection: VisibleSection
        switch direction {
        case .right:
            guard itemIndex == rows[rowIndex].items.count - 1 else { return .native }
            if rowIndex + 1 < rows.count {
                targetRow = rows[rowIndex + 1]; destinationSection = section
            } else {
                guard section.endsAtLastItem, sectionIndex + 1 < layout.sections.count else { return .native }
                let next = layout.sections[sectionIndex + 1]
                guard next.coverageKnown, next.startsAtFirstItem, let first = makeRows(next.items)?.first else { return .native }
                targetRow = first; destinationSection = next
            }
        case .left:
            guard itemIndex == 0 else { return .native }
            if rowIndex > 0 {
                targetRow = rows[rowIndex - 1]; destinationSection = section
            } else {
                guard section.startsAtFirstItem, sectionIndex > 0 else { return .native }
                let previous = layout.sections[sectionIndex - 1]
                guard previous.coverageKnown, previous.endsAtLastItem, let last = makeRows(previous.items)?.last else { return .native }
                targetRow = last; destinationSection = previous
            }
        }
        guard fullRow(targetRow, in: layout.viewport),
              let target = direction == .right ? targetRow.items.first : targetRow.items.last,
              target.url != source.url,
              layout.sections.flatMap(\.items).filter({ $0.url == target.url }).count == 1 else { return .native }
        let sourceRow = rows[rowIndex]
        // No overlapping or misordered sections/rows, even if supplied by a
        // future adapter. The corridor covers the full row width, not a diagonal.
        if direction == .right {
            guard targetRow.bounds.minY >= sourceRow.bounds.maxY else { return .native }
        } else {
            guard targetRow.bounds.maxY <= sourceRow.bounds.minY else { return .native }
        }
        let union = sourceRow.bounds.union(targetRow.bounds)
        let corridor = CGRect(x: layout.viewport.minX, y: union.minY, width: layout.viewport.width, height: union.height)
        guard !(section.gaps + destinationSection.gaps).contains(where: { !valid($0) || $0.intersects(corridor) }) else { return .native }
        return .wrap(from: source.url, to: target.url)
    }

    private func fullRow(_ row: Row, in viewport: CGRect) -> Bool {
        row.valid && row.items.allSatisfy { viewport.contains($0.frame) }
    }

    private func valid(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) && rect.width > 0 && rect.height > 0
    }

    private func makeRows(_ items: [VisibleItem]) -> [Row]? {
        guard !items.isEmpty, items.allSatisfy({ valid($0.frame) }) else { return nil }
        let sorted = items.sorted { $0.frame.midY == $1.frame.midY ? $0.frame.minX < $1.frame.minX : $0.frame.midY < $1.frame.midY }
        var result: [Row] = []
        for item in sorted {
            if let last = result.last, let reference = last.items.first,
               abs(item.frame.midY - reference.frame.midY) <= min(item.frame.height, reference.frame.height) / 4 {
                result[result.count - 1].items.append(item)
            } else { result.append(Row(items: [item])) }
        }
        for index in result.indices {
            result[index].items.sort { $0.frame.minX < $1.frame.minX }
            if index > 0, result[index].bounds.minY < result[index - 1].bounds.maxY {
                result[index].valid = false; result[index - 1].valid = false
            }
            for pair in zip(result[index].items, result[index].items.dropFirst()) {
                if pair.0.frame.maxX > pair.1.frame.minX { result[index].valid = false }
            }
        }
        return result
    }
}
