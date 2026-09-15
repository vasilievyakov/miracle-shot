import CoreGraphics
import Foundation

/// The active annotation tool.
public enum Tool: String, Sendable, Equatable, CaseIterable {
    case select, arrow, line, rect, ellipse, freehand, text, step, blur, highlight, crop
}

/// Input the AppKit canvas forwards to the session. Points are in source image pixels.
public enum EditorEvent: Sendable, Equatable {
    case mouseDown(CGPoint, shift: Bool)
    case mouseDragged(CGPoint)
    case mouseUp(CGPoint)
    case selectTool(Tool)
    case setStyle(AnnotationStyle)
    case setBlurMode(BlurMode)
    case textCommitted(id: UUID, string: String)
    case textCancelled(id: UUID)
    /// Re-opens editing of an existing text annotation (double-click).
    case editText(id: UUID)
    case deleteSelection
    case escape
    case undo, redo
    case setBackground(BackgroundPreset?)
    case cropConfirm, cropCancel
}

/// What the UI must do after an event; the session never touches AppKit.
public enum EditorEffect: Sendable, Equatable {
    case beginTextEditing(id: UUID)
    case endTextEditing
}

/// An interaction in progress: something the user has started but not yet committed.
public enum Transient: Sendable, Equatable {
    case drawing(Annotation)
    case moving(id: UUID, last: CGPoint)
    case resizing(id: UUID, handle: Handle)
    case cropping(anchor: CGPoint, rect: CGRect)
}

/// Pure interaction state machine: turns mouse/keyboard events into `Document` mutations. Holds no
/// AppKit state; `EditorCanvasView` drives it and draws whatever it reports back.
public struct EditorSession: Sendable, Equatable {
    public private(set) var document: Document
    public private(set) var undo: UndoStack<Document>
    public var tool: Tool
    public var style: AnnotationStyle
    public var blurMode: BlurMode
    public private(set) var selectedID: UUID?
    public private(set) var transient: Transient?
    /// The crop rect being edited while `tool == .crop` (starts as the current crop or the full image).
    public private(set) var pendingCrop: CGRect?
    /// Hit tolerance and handle radius in image pixels; the canvas updates them when the zoom changes.
    public var hitTolerance: CGFloat
    public var handleTolerance: CGFloat
    /// Text metrics come from Core too (`AnnotationBounds.bounds(of:)`), injected so tests can use a fixed box.
    public var bounds: @Sendable (Annotation) -> CGRect

    // MARK: Private transient bookkeeping (not part of the public contract)

    /// The document right before a move/resize drag started; pushed to `undo` lazily on the first
    /// `mouseDragged`, so a click without a drag pushes nothing.
    private var dragSnapshot: Document?
    /// The document right before a shape draw started; pushed to `undo` only if the drawn shape commits.
    private var drawingDocumentBefore: Document?
    /// The fixed corner/endpoint a rect-like shape is drawn from.
    private var drawAnchor: CGPoint?
    private var pendingTextEdit: PendingTextEdit?

    private struct PendingTextEdit: Sendable, Equatable {
        let id: UUID
        let origin: TextEditOrigin
    }

    private enum TextEditOrigin: Sendable, Equatable {
        /// A brand-new annotation created by a text-tool `mouseDown`; `documentBefore` is the state to
        /// restore to if the text is cancelled or committed empty (nothing was ever pushed to `undo`).
        case created(documentBefore: Document)
        /// An existing annotation re-opened for editing (`editText`); nothing changes until commit.
        case existing
    }

    public init(document: Document, style: AnnotationStyle, bounds: @escaping @Sendable (Annotation) -> CGRect = AnnotationBounds.bounds(of:)) {
        self.document = document
        self.undo = UndoStack()
        self.tool = .select
        self.style = style
        self.blurMode = .gaussian
        self.selectedID = nil
        self.transient = nil
        self.pendingCrop = nil
        self.hitTolerance = 6
        self.handleTolerance = 6
        self.bounds = bounds
        self.dragSnapshot = nil
        self.drawingDocumentBefore = nil
        self.drawAnchor = nil
        self.pendingTextEdit = nil
    }

    public var canUndo: Bool { undo.canUndo }
    public var canRedo: Bool { undo.canRedo }

    public var selected: Annotation? {
        guard let selectedID else { return nil }
        return document.annotation(id: selectedID)
    }

    /// The document plus the in-progress annotation, for the canvas to draw.
    public var displayAnnotations: [Annotation] {
        if case .drawing(let annotation) = transient {
            return document.annotations + [annotation]
        }
        return document.annotations
    }

    // MARK: Event handling

    @discardableResult
    public mutating func handle(_ event: EditorEvent) -> EditorEffect? {
        switch event {
        case .mouseDown(let point, _):
            // `shift` (aspect-ratio lock while resizing a rect) is not implemented; the parameter is
            // accepted for forward compatibility and currently ignored.
            return handleMouseDown(point)
        case .mouseDragged(let point):
            handleMouseDragged(point)
            return nil
        case .mouseUp(let point):
            handleMouseUp(point)
            return nil
        case .selectTool(let newTool):
            handleSelectTool(newTool)
            return nil
        case .setStyle(let newStyle):
            handleSetStyle(newStyle)
            return nil
        case .setBlurMode(let mode):
            blurMode = mode
            return nil
        case .textCommitted(let id, let string):
            return handleTextCommitted(id: id, string: string)
        case .textCancelled(let id):
            return handleTextCancelled(id: id)
        case .editText(let id):
            return handleEditText(id: id)
        case .deleteSelection:
            handleDeleteSelection()
            return nil
        case .escape:
            handleEscape()
            return nil
        case .undo:
            if let restored = undo.undo(current: document) { document = restored }
            selectedID = nil
            transient = nil
            return nil
        case .redo:
            if let restored = undo.redo(current: document) { document = restored }
            selectedID = nil
            transient = nil
            return nil
        case .setBackground(let preset):
            undo.push(document)
            document.background = preset
            return nil
        case .cropConfirm:
            handleCropConfirm()
            return nil
        case .cropCancel:
            handleCropCancel()
            return nil
        }
    }

    // MARK: mouseDown

    private mutating func handleMouseDown(_ point: CGPoint) -> EditorEffect? {
        switch tool {
        case .select:
            handleSelectMouseDown(point)
            return nil
        case .arrow, .line, .rect, .ellipse, .blur, .highlight, .freehand:
            handleDrawMouseDown(point)
            return nil
        case .text:
            return handleTextMouseDown(point)
        case .step:
            handleStepMouseDown(point)
            return nil
        case .crop:
            transient = .cropping(anchor: clampToImage(point), rect: .zero)
            return nil
        }
    }

    private mutating func handleSelectMouseDown(_ point: CGPoint) {
        if let selectedID, let selectedAnnotation = document.annotation(id: selectedID),
           let handle = AnnotationHandles.handle(at: point, in: selectedAnnotation, tolerance: handleTolerance) {
            dragSnapshot = document
            transient = .resizing(id: selectedID, handle: handle)
            return
        }
        if let hit = AnnotationHitTest.hit(point, in: document.annotations, tolerance: hitTolerance, bounds: bounds) {
            selectedID = hit.id
            dragSnapshot = document
            transient = .moving(id: hit.id, last: point)
            return
        }
        selectedID = nil
        transient = nil
    }

    private mutating func handleDrawMouseDown(_ point: CGPoint) {
        drawingDocumentBefore = document
        drawAnchor = point
        let shape: AnnotationShape
        switch tool {
        case .arrow: shape = .arrow(from: point, to: point)
        case .line: shape = .line(from: point, to: point)
        case .rect: shape = .rect(CGRect(origin: point, size: .zero))
        case .ellipse: shape = .ellipse(CGRect(origin: point, size: .zero))
        case .blur: shape = .blur(CGRect(origin: point, size: .zero), mode: blurMode)
        case .highlight: shape = .highlight(CGRect(origin: point, size: .zero))
        case .freehand: shape = .freehand([point])
        case .select, .text, .step, .crop: return   // unreachable: dispatched only for drawing tools
        }
        transient = .drawing(Annotation(shape: shape, style: style))
    }

    private mutating func handleTextMouseDown(_ point: CGPoint) -> EditorEffect {
        let documentBefore = document
        let annotation = Annotation(shape: .text(origin: point, string: ""), style: style)
        document.add(annotation)
        selectedID = annotation.id
        pendingTextEdit = PendingTextEdit(id: annotation.id, origin: .created(documentBefore: documentBefore))
        return .beginTextEditing(id: annotation.id)
    }

    private mutating func handleStepMouseDown(_ point: CGPoint) {
        undo.push(document)
        let annotation = Annotation(shape: .step(center: point, number: document.nextStepNumber), style: style)
        document.add(annotation)
        selectedID = annotation.id
    }

    // MARK: mouseDragged

    private mutating func handleMouseDragged(_ point: CGPoint) {
        switch transient {
        case .drawing(var annotation):
            updateDrawingShape(&annotation, to: point)
            transient = .drawing(annotation)
        case .moving(let id, let last):
            pushDragSnapshotIfNeeded()
            guard let annotation = document.annotation(id: id) else { return }
            let delta = CGPoint(x: point.x - last.x, y: point.y - last.y)
            document.update(annotation.moved(by: delta))
            transient = .moving(id: id, last: point)
        case .resizing(let id, let handle):
            pushDragSnapshotIfNeeded()
            guard let annotation = document.annotation(id: id) else { return }
            document.update(AnnotationHandles.resized(annotation, handle: handle, to: point))
        case .cropping(let anchor, _):
            let clamped = clampToImage(point)
            let rect = CGRect(x: anchor.x, y: anchor.y, width: clamped.x - anchor.x, height: clamped.y - anchor.y).standardized
            transient = .cropping(anchor: anchor, rect: rect)
        case nil:
            break
        }
    }

    private mutating func pushDragSnapshotIfNeeded() {
        guard let snapshot = dragSnapshot else { return }
        undo.push(snapshot)
        dragSnapshot = nil
    }

    private func updateDrawingShape(_ annotation: inout Annotation, to point: CGPoint) {
        guard let anchor = drawAnchor else { return }
        let standardizedRect = CGRect(x: anchor.x, y: anchor.y, width: point.x - anchor.x, height: point.y - anchor.y).standardized
        switch annotation.shape {
        case .arrow(let from, _):
            annotation.shape = .arrow(from: from, to: point)
        case .line(let from, _):
            annotation.shape = .line(from: from, to: point)
        case .rect:
            annotation.shape = .rect(standardizedRect)
        case .ellipse:
            annotation.shape = .ellipse(standardizedRect)
        case .blur(_, let mode):
            annotation.shape = .blur(standardizedRect, mode: mode)
        case .highlight:
            annotation.shape = .highlight(standardizedRect)
        case .freehand(var points):
            points.append(point)
            annotation.shape = .freehand(points)
        case .text, .step:
            break
        }
    }

    // MARK: mouseUp

    private mutating func handleMouseUp(_ point: CGPoint) {
        switch transient {
        case .drawing(let annotation):
            transient = nil
            if shouldCommit(annotation) {
                if let before = drawingDocumentBefore { undo.push(before) }
                document.add(annotation)
                selectedID = annotation.id
            }
            drawingDocumentBefore = nil
            drawAnchor = nil
        case .moving, .resizing:
            transient = nil
            dragSnapshot = nil
        case .cropping(_, let rect):
            transient = nil
            if rect.width > 8, rect.height > 8 {
                pendingCrop = rect
            }
        case nil:
            break
        }
    }

    private func shouldCommit(_ annotation: Annotation) -> Bool {
        switch annotation.shape {
        case .rect(let rect), .ellipse(let rect), .blur(let rect, _), .highlight(let rect):
            let standardized = rect.standardized
            return standardized.width > 3 && standardized.height > 3
        case .arrow(let from, let to), .line(let from, let to):
            return hypot(to.x - from.x, to.y - from.y) > 3
        case .freehand(let points):
            return points.count >= 2
        case .text, .step:
            return false
        }
    }

    // MARK: selectTool

    private mutating func handleSelectTool(_ newTool: Tool) {
        if tool == .crop, pendingCrop != nil, newTool != .crop {
            pendingCrop = nil
            if case .cropping = transient { transient = nil }
        }
        tool = newTool
        if newTool == .crop {
            pendingCrop = document.cropRect ?? CGRect(origin: .zero, size: document.sourceSize)
        }
    }

    // MARK: setStyle

    private mutating func handleSetStyle(_ newStyle: AnnotationStyle) {
        style = newStyle
        guard let selectedID, var annotation = document.annotation(id: selectedID) else { return }
        undo.push(document)
        annotation.style = newStyle
        document.update(annotation)
    }

    // MARK: deleteSelection

    private mutating func handleDeleteSelection() {
        guard let selectedID else { return }
        undo.push(document)
        document.remove(id: selectedID)
        self.selectedID = nil
    }

    // MARK: escape

    private mutating func handleEscape() {
        if tool == .crop {
            pendingCrop = nil
            transient = nil
            tool = .select
        } else if case .drawing = transient {
            transient = nil
            drawingDocumentBefore = nil
            drawAnchor = nil
        } else {
            selectedID = nil
        }
    }

    // MARK: crop confirm/cancel

    private mutating func handleCropConfirm() {
        undo.push(document)
        let full = CGRect(origin: .zero, size: document.sourceSize)
        if let pendingCrop, pendingCrop != full {
            document.cropRect = pendingCrop
        } else {
            document.cropRect = nil
        }
        pendingCrop = nil
        transient = nil
        tool = .select
    }

    private mutating func handleCropCancel() {
        pendingCrop = nil
        transient = nil
        tool = .select
    }

    // MARK: text editing

    private mutating func handleEditText(id: UUID) -> EditorEffect? {
        guard let annotation = document.annotation(id: id), case .text = annotation.shape else { return nil }
        selectedID = id
        pendingTextEdit = PendingTextEdit(id: id, origin: .existing)
        return .beginTextEditing(id: id)
    }

    private mutating func handleTextCommitted(id: UUID, string: String) -> EditorEffect {
        guard let annotation = document.annotation(id: id) else {
            pendingTextEdit = nil
            return .endTextEditing
        }
        let origin: TextEditOrigin
        if let pendingTextEdit, pendingTextEdit.id == id {
            origin = pendingTextEdit.origin
        } else {
            origin = .existing
        }
        pendingTextEdit = nil

        switch origin {
        case .created(let documentBefore):
            if string.isEmpty {
                document = documentBefore
                if selectedID == id { selectedID = nil }
            } else {
                undo.push(documentBefore)
                document.update(withText(annotation, string: string))
            }
        case .existing:
            let oldString = currentString(of: annotation)
            if string != oldString {
                undo.push(document)
                if string.isEmpty {
                    document.remove(id: id)
                    if selectedID == id { selectedID = nil }
                } else {
                    document.update(withText(annotation, string: string))
                }
            }
        }
        return .endTextEditing
    }

    private mutating func handleTextCancelled(id: UUID) -> EditorEffect {
        defer { pendingTextEdit = nil }
        if let pendingTextEdit, pendingTextEdit.id == id, case .created(let documentBefore) = pendingTextEdit.origin {
            document = documentBefore
            if selectedID == id { selectedID = nil }
        }
        // An `.existing` (or untracked) origin leaves the annotation exactly as it was.
        return .endTextEditing
    }

    private func withText(_ annotation: Annotation, string: String) -> Annotation {
        var copy = annotation
        copy.shape = .text(origin: originPoint(of: annotation), string: string)
        return copy
    }

    private func originPoint(of annotation: Annotation) -> CGPoint {
        if case .text(let origin, _) = annotation.shape { return origin }
        return .zero
    }

    private func currentString(of annotation: Annotation) -> String {
        if case .text(_, let string) = annotation.shape { return string }
        return ""
    }

    // MARK: geometry helpers

    private func clampToImage(_ point: CGPoint) -> CGPoint {
        let size = document.sourceSize
        return CGPoint(x: min(max(point.x, 0), size.width), y: min(max(point.y, 0), size.height))
    }

    // MARK: Equatable

    public static func == (lhs: EditorSession, rhs: EditorSession) -> Bool {
        lhs.document == rhs.document
            && lhs.undo.undoStates == rhs.undo.undoStates
            && lhs.undo.redoStates == rhs.undo.redoStates
            && lhs.undo.limit == rhs.undo.limit
            && lhs.tool == rhs.tool
            && lhs.style == rhs.style
            && lhs.blurMode == rhs.blurMode
            && lhs.selectedID == rhs.selectedID
            && lhs.transient == rhs.transient
            && lhs.pendingCrop == rhs.pendingCrop
            && lhs.hitTolerance == rhs.hitTolerance
            && lhs.handleTolerance == rhs.handleTolerance
            && lhs.pendingTextEdit == rhs.pendingTextEdit
    }
}
