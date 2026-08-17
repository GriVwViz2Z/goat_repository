#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum IconError: Error, CustomStringConvertible {
    case usage
    case cannotRead(String)
    case cannotCreateContext
    case cannotCreateImage
    case cannotWrite(String)

    var description: String {
        switch self {
        case .usage:
            "usage: process-icon.swift INPUT OUTPUT"
        case let .cannotRead(path):
            "cannot read image: \(path)"
        case .cannotCreateContext:
            "cannot create image context"
        case .cannotCreateImage:
            "cannot create processed image"
        case let .cannotWrite(path):
            "cannot write image: \(path)"
        }
    }
}

private func loadImage(path: String) throws -> CGImage {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let source = CGImageSourceCreateWithURL(url, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw IconError.cannotRead(path) }
    return image
}

private func macOSMaster(from image: CGImage) throws -> CGImage {
    let canvasSize = 1024
    let artworkSide = 824
    let inset = (canvasSize - artworkSide) / 2
    let artworkRect = CGRect(x: inset, y: inset, width: artworkSide, height: artworkSide)

    guard let context = CGContext(
        data: nil,
        width: canvasSize,
        height: canvasSize,
        bitsPerComponent: 8,
        bytesPerRow: canvasSize * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw IconError.cannotCreateContext }

    context.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    context.saveGState()
    context.addPath(
        CGPath(
            roundedRect: artworkRect,
            cornerWidth: 185,
            cornerHeight: 185,
            transform: nil
        )
    )
    context.clip()
    context.draw(image, in: artworkRect)
    context.restoreGState()

    guard let result = context.makeImage() else { throw IconError.cannotCreateImage }
    return result
}

private func writePNG(_ image: CGImage, path: String) throws {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let destination = CGImageDestinationCreateWithURL(
        url,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else { throw IconError.cannotWrite(path) }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw IconError.cannotWrite(path) }
}

do {
    guard CommandLine.arguments.count == 3 else { throw IconError.usage }
    let source = try loadImage(path: CommandLine.arguments[1])
    let master = try macOSMaster(from: source)
    try writePNG(master, path: CommandLine.arguments[2])
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
