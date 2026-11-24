import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import Zerus_Native

func makeChatTestImage(in root: URL) throws -> MacChatImage {
    let context = try XCTUnwrap(CGContext(data: nil, width: 12, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(CGColor(gray: 0.7, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
    let original = root.appendingPathComponent("Synthetic.png"), destination = try XCTUnwrap(CGImageDestinationCreateWithURL(original as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
    return try MacChatImage.prepare(original)
}
