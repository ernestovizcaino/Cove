#!/usr/bin/env swift
//
// Regenerates Cove's app icon from source geometry.
//
//   swift Scripts/make-icon.swift
//
// The mark is a thick ring broken at the lower right, where a wedge grows out of
// the gap: a speech bubble and its tail, drawn as one continuous silhouette.
// Everything is computed from a single centre, radius and stroke weight, so the
// icon can be re-rendered at any size without redrawing it by hand.

import AppKit
import SwiftUI

// MARK: - Geometry

let canvas: CGFloat = 1024
/// Apple's macOS grid: an 824pt body centred in a 1024pt canvas.
let tileSize: CGFloat = 824
let tileRadius: CGFloat = 185.4

// The tail hangs below the circle, so the centre sits high of true centre to put
// the mark's visual mass in the middle of the tile.
let markCentre = CGPoint(x: 516, y: 474)
let markRadius: CGFloat = 198
let markWeight: CGFloat = 92

/// Screen angles: 0° points right, and angles increase clockwise because y grows
/// downwards. The tail sits at the bottom left; at 45° it reads as the leg of a Q.
let outerRadius = markRadius + markWeight / 2
let innerRadius = markRadius - markWeight / 2
let tailStart: CGFloat = 95
let tailEnd: CGFloat = 128
let tailAngle: CGFloat = 112
let tailReach: CGFloat = 336

func point(_ degrees: CGFloat, _ radius: CGFloat) -> CGPoint {
    let r = degrees * .pi / 180
    return CGPoint(x: markCentre.x + radius * cos(r), y: markCentre.y + radius * sin(r))
}

// MARK: - Colors

extension Color {
    init(_ hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

let tileTop = Color(0x1B5566)
let tileBottom = Color(0x0A2530)
let markTop = Color(0xFFFFFF)
let markBottom = Color(0xDCE9E8)

// MARK: - Icon

/// One closed outline plus a concentric hole, filled even-odd. Stroking an arc and
/// dropping a triangle on top leaves lumps where the two meet; this keeps the tail
/// and the bubble a single silhouette.
struct Mark: View {
    var body: some View {
        Path { path in
            path.addArc(center: markCentre, radius: outerRadius,
                        startAngle: .degrees(tailEnd), endAngle: .degrees(tailStart + 360),
                        clockwise: false)
            path.addLine(to: point(tailAngle, tailReach))
            path.closeSubpath()

            path.addEllipse(in: CGRect(x: markCentre.x - innerRadius, y: markCentre.y - innerRadius,
                                       width: innerRadius * 2, height: innerRadius * 2))
        }
        .fill(
            LinearGradient(colors: [markTop, markBottom], startPoint: .top, endPoint: .bottom),
            style: FillStyle(eoFill: true)
        )
        .frame(width: canvas, height: canvas)
    }
}

struct Icon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: tileRadius, style: .continuous)
                .fill(
                    LinearGradient(colors: [tileTop, tileBottom],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    // A single hairline of light along the top edge, the way a
                    // physical tile would catch it. Keeps the tile from reading flat.
                    RoundedRectangle(cornerRadius: tileRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.01)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 2.5
                        )
                )
                .frame(width: tileSize, height: tileSize)

            Mark()
        }
        .frame(width: canvas, height: canvas)
    }
}

// MARK: - Render

@MainActor
func png(at size: CGFloat) -> Data? {
    let renderer = ImageRenderer(content: Icon().frame(width: canvas, height: canvas))
    renderer.scale = size / canvas
    guard let cgImage = renderer.cgImage else { return nil }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = NSSize(width: size, height: size)
    return rep.representation(using: .png, properties: [:])
}

// macOS wants each point size at 1x and 2x.
let variants: [(point: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)
]

try MainActor.assumeIsolated {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let iconSet = root.appending(path: "Cove/Resources/Assets.xcassets/AppIcon.appiconset")
    try? FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

    var images: [[String: String]] = []
    for variant in variants {
        let pixels = CGFloat(variant.point * variant.scale)
        let name = "icon_\(variant.point)x\(variant.point)\(variant.scale == 2 ? "@2x" : "").png"
        guard let data = png(at: pixels) else {
            FileHandle.standardError.write(Data("Failed to render \(name)\n".utf8))
            exit(1)
        }
        try data.write(to: iconSet.appending(path: name))
        images.append([
            "size": "\(variant.point)x\(variant.point)",
            "idiom": "mac",
            "filename": name,
            "scale": "\(variant.scale)x"
        ])
        print("rendered \(name) (\(Int(pixels))px)")
    }

    let contents: [String: Any] = [
        "images": images,
        "info": ["version": 1, "author": "xcode"]
    ]
    let json = try JSONSerialization.data(withJSONObject: contents,
                                          options: [.prettyPrinted, .sortedKeys])
    try json.write(to: iconSet.appending(path: "Contents.json"))

    // A full-size copy for README screenshots and the GitHub social preview.
    if let data = png(at: canvas) {
        try data.write(to: root.appending(path: "docs/icon-1024.png"))
        print("rendered docs/icon-1024.png")
    }
    print("done")
}
