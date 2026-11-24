import CoreGraphics
import Foundation
import XCTest

/// The element tree for `captureDom`, as Appium XCUITest page source (`<AppiumAUT>`), which the backend
/// reads as an iOS DOM. Frames are in points, scaled by `devicePixelRatio`.
internal struct DomSnapshot: Hashable, Sendable {
    let xml: Data
    /// Pixels per point of the screenshot, sent as `devicePixelRatio`.
    let devicePixelRatio: Double
}

/// One element of the tree. Kept apart from `XCUIElementSnapshot` so tests can build trees by hand.
internal struct DomNode: Hashable, Sendable {
    var type: String
    var identifier: String = ""
    var label: String = ""
    var value: String?
    var enabled = true
    var selected = false
    /// `nil` when it can't be read.
    var accessible: Bool?
    /// In screen points.
    var frame: CGRect = .zero
    var children: [DomNode] = []
}

internal enum DomCapture {
    /// Reads `element`'s tree. `origin` is the uploaded image's top-left and `screen` the screen, in points.
    @MainActor
    static func capture(
        _ element: XCUIElement, origin: CGPoint, screen: CGRect, devicePixelRatio: Double
    ) throws -> DomSnapshot {
        let snapshot = try element.snapshot()
        let reader = AccessibilityReader().flatMap { $0.isElement(snapshot) == nil ? nil : $0 }
        let root = node(from: snapshot, reader: reader, insideAccessibilityElement: false)
        return DomSnapshot(xml: document(root, origin: origin, screen: screen), devicePixelRatio: devicePixelRatio)
    }

    @MainActor
    private static func node(
        from snapshot: XCUIElementSnapshot, reader: AccessibilityReader?, insideAccessibilityElement: Bool
    ) -> DomNode {
        let type = snapshot.elementType
        var isElement = false
        var accessible: Bool?
        if let reader {
            isElement = reader.isElement(snapshot) ?? false
            accessible = isAccessible(type, isElement: isElement, insideAccessibilityElement: insideAccessibilityElement) {
                snapshot.children.first.flatMap(reader.isElement) ?? false
            }
        }
        let childrenInside = insideAccessibilityElement || (type != .table && isElement)
        return DomNode(
            type: typeName(type),
            identifier: snapshot.identifier,
            label: snapshot.label,
            value: text(snapshot.value) ?? snapshot.placeholderValue.flatMap { $0.isEmpty ? nil : $0 },
            enabled: snapshot.isEnabled,
            selected: snapshot.isSelected,
            accessible: accessible,
            frame: snapshot.frame,
            children: snapshot.children.map {
                node(from: $0, reader: reader, insideAccessibilityElement: childrenInside)
            }
        )
    }

    /// Same rules as Appium's WebDriverAgent.
    static func isAccessible(
        _ type: XCUIElement.ElementType, isElement: Bool, insideAccessibilityElement: Bool,
        firstChildIsElement: () -> Bool
    ) -> Bool {
        guard !insideAccessibilityElement else { return false }
        switch type {
        case .cell: return isElement || firstChildIsElement()
        case .textField, .secureTextField: return true
        default: return isElement
        }
    }

    /// The page source for `root`, with frames moved so `origin` becomes `(0, 0)`.
    static func document(_ root: DomNode, origin: CGPoint, screen: CGRect) -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<AppiumAUT>\n"
        write(root, index: 0, origin: origin, screen: screen, to: &xml)
        xml += "</AppiumAUT>\n"
        return Data(xml.utf8)
    }

    private static func write(_ node: DomNode, index: Int, origin: CGPoint, screen: CGRect, to xml: inout String) {
        var attributes: [(String, String)] = [("type", node.type)]
        // Appium's `name` is the accessibility identifier, or the label when there is none.
        let name = node.identifier.isEmpty ? node.label : node.identifier
        if !name.isEmpty { attributes.append(("name", name)) }
        if !node.label.isEmpty { attributes.append(("label", node.label)) }
        if let value = node.value { attributes.append(("value", value)) }
        attributes.append(("enabled", String(node.enabled)))
        attributes.append(("visible", String(isVisible(node.frame, on: screen))))
        attributes.append(("selected", String(node.selected)))
        if let accessible = node.accessible { attributes.append(("accessible", String(accessible))) }
        let frame = node.frame
        if let x = wholeNumber(frame.minX - origin.x), let y = wholeNumber(frame.minY - origin.y),
           let width = wholeNumber(frame.width), let height = wholeNumber(frame.height) {
            attributes += [("x", String(x)), ("y", String(y)), ("width", String(width)), ("height", String(height))]
        }
        attributes.append(("index", String(index)))

        xml += "<\(node.type)"
        for (key, value) in attributes { xml += " \(key)=\"\(escape(value))\"" }
        guard !node.children.isEmpty else {
            xml += "/>\n"
            return
        }
        xml += ">\n"
        for (childIndex, child) in node.children.enumerated() {
            write(child, index: childIndex, origin: origin, screen: screen, to: &xml)
        }
        xml += "</\(node.type)>\n"
    }

    /// Some elements, such as hidden ones, report an infinite or empty frame. Those, and frames with a
    /// negative size, are never visible.
    static func isVisible(_ frame: CGRect, on screen: CGRect) -> Bool {
        guard PixelRegion.isUsable(frame) else { return false }
        let visible = frame.intersection(screen)
        return !visible.isNull && visible.width > 0 && visible.height > 0
    }

    /// `value` rounded, or `nil` when it isn't finite or doesn't fit in an `Int`. `Int(_:)` would crash the
    /// test process instead, and a finite frame can still be far out of range.
    private static func wholeNumber(_ value: CGFloat) -> Int? {
        Int(exactly: value.rounded())
    }

    /// Escapes XML markup and drops characters XML 1.0 can't hold.
    static func escape(_ value: String) -> String {
        var escaped = ""
        escaped.unicodeScalars.reserveCapacity(value.unicodeScalars.count)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&apos;"
            case "\n": escaped += "&#10;"
            case "\r": escaped += "&#13;"
            case "\t": escaped += "&#9;"
            default:
                let code = scalar.value
                let allowed = (0x20...0xD7FF).contains(code) || (0xE000...0xFFFD).contains(code)
                    || (0x10000...0x10FFFF).contains(code)
                if allowed { escaped.unicodeScalars.append(scalar) }
            }
        }
        return escaped
    }

    /// Switches report `0` or `1`, sliders a number, text fields their text.
    private static func text(_ value: Any?) -> String? {
        switch value {
        case let string as String: return string.isEmpty ? nil : string
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    static func typeName(_ type: XCUIElement.ElementType) -> String {
        let index = Int(type.rawValue)
        return typeNames.indices.contains(index) ? "XCUIElementType" + typeNames[index] : "XCUIElementTypeOther"
    }

    /// `XCUIElement.ElementType` raw values 0 to 82, in the order of `XCUIElementTypes.h`.
    private static let typeNames = [
        "Any", "Other", "Application", "Group", "Window", "Sheet", "Drawer", "Alert", "Dialog", "Button",
        "RadioButton", "RadioGroup", "CheckBox", "DisclosureTriangle", "PopUpButton", "ComboBox", "MenuButton",
        "ToolbarButton", "Popover", "Keyboard", "Key", "NavigationBar", "TabBar", "TabGroup", "Toolbar",
        "StatusBar", "Table", "TableRow", "TableColumn", "Outline", "OutlineRow", "Browser", "CollectionView",
        "Slider", "PageIndicator", "ProgressIndicator", "ActivityIndicator", "SegmentedControl", "Picker",
        "PickerWheel", "Switch", "Toggle", "Link", "Image", "Icon", "SearchField", "ScrollView", "ScrollBar",
        "StaticText", "TextField", "SecureTextField", "DatePicker", "TextView", "Menu", "MenuItem", "MenuBar",
        "MenuBarItem", "Map", "WebView", "IncrementArrow", "DecrementArrow", "Timeline", "RatingIndicator",
        "ValueIndicator", "SplitGroup", "Splitter", "RelevanceIndicator", "ColorWell", "HelpTag", "Matte",
        "DockItem", "Ruler", "RulerMarker", "Grid", "LevelIndicator", "Cell", "LayoutArea", "LayoutItem",
        "Handle", "Stepper", "Tab", "TouchBar", "StatusItem"
    ]
}

/// Reads the accessibility element flag through XCTest's private API, like WebDriverAgent.
@MainActor
internal struct AccessibilityReader {
    private typealias Attributes = @convention(c) (
        AnyObject, Selector, AnyObject, NSArray, AutoreleasingUnsafeMutablePointer<NSError?>?
    ) -> NSDictionary?

    private let client: NSObject
    private let selector: Selector
    private let attributes: Attributes
    private let attributeName: NSString

    init?() {
        #if os(iOS)
        let device = XCUIDevice.shared as NSObject
        let selector = NSSelectorFromString("attributesForElement:attributes:error:")
        guard device.responds(to: NSSelectorFromString("accessibilityInterface")),
              let client = device.value(forKey: "accessibilityInterface") as? NSObject,
              client.responds(to: selector),
              let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "XC_kAXXCAttributeIsElement")
        else { return nil }
        self.client = client
        self.selector = selector
        attributes = unsafeBitCast(client.method(for: selector), to: Attributes.self)
        attributeName = symbol.load(as: Unmanaged<NSString>.self).takeUnretainedValue()
        #else
        return nil
        #endif
    }

    func isElement(_ snapshot: XCUIElementSnapshot) -> Bool? {
        guard let object = snapshot as? NSObject, object.responds(to: NSSelectorFromString("accessibilityElement")),
              let element = object.value(forKey: "accessibilityElement") as AnyObject?
        else { return nil }
        var error: NSError?
        let result = attributes(client, selector, element, [attributeName] as NSArray, &error)
        return (result?[attributeName] as? NSNumber)?.boolValue
    }
}
