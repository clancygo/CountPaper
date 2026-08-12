import Foundation

// ICNS files can contain PNG payloads directly. Keeping this tiny generator in
// the project makes the app icon reproducible without third-party tooling.
guard CommandLine.arguments.count == 3 else {
    fputs("Usage: make-icns.swift input-1024.png output.icns\\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let png = try Data(contentsOf: inputURL)

func be32(_ value: UInt32) -> [UInt8] {
    [UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
}

let chunkLength = UInt32(8 + png.count)
let totalLength = UInt32(8 + Int(chunkLength))
var icns = Data([0x69, 0x63, 0x6e, 0x73]) // "icns"
icns.append(contentsOf: be32(totalLength))
icns.append(contentsOf: [0x69, 0x63, 0x31, 0x30]) // "ic10", 1024 × 1024 PNG
icns.append(contentsOf: be32(chunkLength))
icns.append(png)
try icns.write(to: outputURL, options: .atomic)
