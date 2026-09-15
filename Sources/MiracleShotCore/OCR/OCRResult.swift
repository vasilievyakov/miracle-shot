import CoreGraphics

/// One recognized piece of text from an OCR pass.
public struct TextBlock: Sendable, Equatable {
    public var text: String
    /// Pixel rect in the source image, origin top-left.
    public var rect: CGRect
    public var confidence: Float

    public init(text: String, rect: CGRect, confidence: Float) {
        self.text = text
        self.rect = rect
        self.confidence = confidence
    }
}

/// All text blocks recognized in one image, with assembly into reading-order plain text.
public struct OCRResult: Sendable, Equatable {
    public var blocks: [TextBlock]

    public init(blocks: [TextBlock]) {
        self.blocks = blocks
    }

    public var isEmpty: Bool { blocks.isEmpty }

    /// Blocks grouped into lines by vertical overlap (two blocks share a line when their rects overlap vertically
    /// by more than half of the smaller height), lines ordered top to bottom, blocks in a line left to right,
    /// blocks joined with a space, lines with "\n". Paragraph breaks (vertical gap larger than 1.5 lines) become "\n\n".
    public var text: String {
        let lines = OCRResult.assembleLines(blocks)
        guard var result = lines.first?.text else { return "" }
        for (previous, current) in zip(lines, lines.dropFirst()) {
            let gap = current.top - previous.bottom
            let separator = gap > 1.5 * (previous.bottom - previous.top) ? "\n\n" : "\n"
            result += separator + current.text
        }
        return result
    }

    /// The first `count` non-empty lines of `text`, for notifications.
    public func preview(lines count: Int) -> String {
        text.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .prefix(count)
            .joined(separator: "\n")
    }

    private struct Line {
        var blocks: [TextBlock]
        var top: CGFloat
        var bottom: CGFloat

        var text: String {
            blocks.sorted { $0.rect.minX < $1.rect.minX }.map(\.text).joined(separator: " ")
        }
    }

    /// Sorts blocks top to bottom and groups them into lines. A block joins the current line when its vertical
    /// overlap with the line's reference block (the first block placed on that line) exceeds half of the
    /// smaller of the two heights; otherwise it starts a new line and becomes the new reference.
    private static func assembleLines(_ blocks: [TextBlock]) -> [Line] {
        var lines: [Line] = []
        var reference: TextBlock?
        for block in blocks.sorted(by: { $0.rect.minY < $1.rect.minY }) {
            if let reference, verticalOverlap(reference.rect, block.rect) > min(reference.rect.height, block.rect.height) / 2 {
                lines[lines.count - 1].blocks.append(block)
                lines[lines.count - 1].top = min(lines[lines.count - 1].top, block.rect.minY)
                lines[lines.count - 1].bottom = max(lines[lines.count - 1].bottom, block.rect.maxY)
            } else {
                reference = block
                lines.append(Line(blocks: [block], top: block.rect.minY, bottom: block.rect.maxY))
            }
        }
        return lines
    }

    private static func verticalOverlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
    }
}

/// Converts Vision's normalized, bottom-left-origin observation rects into pixel rects with origin top-left.
public enum OCRMapping {
    public static func pixelRect(normalized: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: normalized.minX * imageSize.width,
            y: imageSize.height - normalized.minY * imageSize.height - normalized.height * imageSize.height,
            width: normalized.width * imageSize.width,
            height: normalized.height * imageSize.height
        )
    }

    public static func block(text: String, normalized: CGRect, confidence: Float, imageSize: CGSize) -> TextBlock {
        TextBlock(text: text, rect: pixelRect(normalized: normalized, imageSize: imageSize), confidence: confidence)
    }
}
