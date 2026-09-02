import CoreGraphics

enum SearchPanelLayout {
    struct SectionMetrics {
        let resultCount: Int
        let usesCalculatorRow: Bool
    }

    static let width: CGFloat = 680
    static let headerHeight: CGFloat = 56
    static let headerHorizontalPadding: CGFloat = 18
    static let headerSpacing: CGFloat = 12
    static let searchIconFrameSize: CGFloat = 24
    static let progressIndicatorFrameSize: CGFloat = 16
    static let cornerRadius: CGFloat = 16
    static let maxResultsViewportHeight: CGFloat = 330
    static let footerHeight: CGFloat = 30
    static let dividerHeight: CGFloat = 1
    static let sectionHeaderHeight: CGFloat = 25
    static let resultRowHeight: CGFloat = 44
    static let calculatorRowHeight: CGFloat = 72
    static let resultsVerticalPadding: CGFloat = 8
    static let noResultsHeight: CGFloat = 60
    static let topInsetFraction: CGFloat = 0.28
    static let bottomMargin: CGFloat = 16

    static var maximumContentHeight: CGFloat {
        headerHeight
            + dividerHeight
            + maxResultsViewportHeight
            + dividerHeight
            + footerHeight
    }

    static var searchIconCenterX: CGFloat {
        headerHorizontalPadding + searchIconFrameSize / 2
    }

    static var queryLeadingX: CGFloat {
        headerHorizontalPadding + searchIconFrameSize + headerSpacing
    }

    static func resultsViewportHeight(sections: [SectionMetrics]) -> CGFloat {
        let contentHeight = sections.reduce(resultsVerticalPadding) { height, section in
            let rowsHeight = section.usesCalculatorRow
                ? calculatorRowHeight
                : CGFloat(section.resultCount) * resultRowHeight
            return height + sectionHeaderHeight + rowsHeight
        }
        return min(contentHeight, maxResultsViewportHeight)
    }

    static func panelHeight(
        hasQuery: Bool,
        isSearching: Bool,
        sections: [SectionMetrics]
    ) -> CGFloat {
        guard hasQuery else { return headerHeight }
        guard !sections.isEmpty else {
            return isSearching ? headerHeight : headerHeight + dividerHeight + noResultsHeight
        }

        return headerHeight
            + dividerHeight
            + resultsViewportHeight(sections: sections)
            + dividerHeight
            + footerHeight
    }

    static func constrainedHeight(contentHeight: CGFloat, visibleFrameHeight: CGFloat) -> CGFloat {
        let availableHeight = visibleFrameHeight * (1 - topInsetFraction) - bottomMargin
        let maximumHeight = max(headerHeight, availableHeight)
        return min(max(headerHeight, contentHeight), maximumHeight)
    }

    static func visibleResultsViewportHeight(desiredHeight: CGFloat, panelHeight: CGFloat) -> CGFloat {
        let chromeHeight = headerHeight + dividerHeight * 2 + footerHeight
        return min(desiredHeight, max(0, panelHeight - chromeHeight))
    }

    static func panelFrame(visibleFrame: CGRect, contentHeight: CGFloat) -> CGRect {
        anchoredFrame(
            visibleFrame: visibleFrame,
            height: constrainedHeight(
                contentHeight: contentHeight,
                visibleFrameHeight: visibleFrame.height
            )
        )
    }

    private static func anchoredFrame(visibleFrame: CGRect, height: CGFloat) -> CGRect {
        let x = visibleFrame.minX + (visibleFrame.width - width) / 2
        let topEdge = visibleFrame.maxY - visibleFrame.height * topInsetFraction
        return CGRect(x: x, y: topEdge - height, width: width, height: height)
    }
}
