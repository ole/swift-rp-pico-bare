import Foundation

/// A command-line tool for computing the checksum for the RP2040 second-stage
/// bootloader (boot2) and writing the checksum into the file. The RP2040 won't
/// boot if the checksum is missing or incorrect.
///
/// This tool performs the same task as the `pad_checksum` Python script in the
/// Raspberry Pi Pico SDK <https://github.com/raspberrypi/pico-sdk/blob/master/src/rp2_common/boot_stage2/pad_checksum>.
/// Writing it in Swift avoids the Python dependency.
///
/// As documented in the RP2040 Datasheet:
///
/// > 2.8.1.3.1. Checksum
/// >
/// > The last four bytes of the image loaded from flash (which we hope is a valid
/// > flash second stage) are a CRC32 checksum of the first 252 bytes.
/// > The parameters of the checksum are:
/// >
/// > - Polynomial: `0x04c11db7`
/// > - Input reflection: no
/// > - Output reflection: no
/// > - Initial value: `0xffffffff`
/// > - Final XOR: 0x00000000
/// > - Checksum value appears as little-endian integer at end of image
/// >
/// > The Bootrom makes 128 attempts of approximately 4 ms each for a total of
/// > approximately 0.5 seconds before giving up and dropping into USB code to load
/// > and checksum the second stage with varying SPI parameters. If it sees a
/// > checksum pass it will immediately jump into the 252-byte payload which
/// > contains the flash second stage.
@main
struct CLI {
    static func main() throws {
        // Do not use the ArgumentParser library <https://github.com/apple/swift-argument-parser>
        // to avoid the dependency. This is fine because this is not a public
        // tool, we're only calling it from within the build process.
        // If we ever need ArgumentParser for other reasons, we should use it
        // here too.
        if CommandLine.arguments.count != 3 {
            throw CLIError(message: "Usage: \(CommandLine.arguments[0]) <input-file> <output-file>")
        }

        let inputFile: String = CommandLine.arguments[1]
        let outputFile: String = CommandLine.arguments[2]

        let inputURL = URL(fileURLWithPath: inputFile)
        let inputData = try Data(contentsOf: inputURL)

        // Boot2 must be exactly 256 bytes long, including the checksum.
        let paddedSize = 256
        let checksumLength = 4
        let maxInputLength = paddedSize - checksumLength
        let paddingLength = maxInputLength - inputData.count
        guard paddingLength >= 0 else {
            throw CLIError(message: "Input file size (\(inputData.count) bytes) is too large for output size (\(paddedSize) bytes). Maximum allowed input file size: \(maxInputLength) bytes")
        }

        var padded = Array(inputData)
        padded.append(contentsOf: Array(repeating: 0, count: paddingLength))

        let checksum = crc32(
            message: padded,
            polynomial: 0x04c1_1db7,
            initialValue: 0xffff_ffff,
            xorOut: 0x0000_0000
        )
        var littleEndianChecksum = checksum.littleEndian
        var checksummed = padded
        withUnsafeBytes(of: &littleEndianChecksum) { buffer in
            for byte in buffer {
                checksummed.append(byte)
            }
        }

        // Write output file as assembly code that places the 256 bytes into the
        // correct section. The output file must then be assembled again in
        // another build step.
        //
        // We follow the formatting of the pad_checksum Python script in the
        // RP2040 SDK.
        var output = """
            // Padded and checksummed copy of: \(inputURL.absoluteURL.path)

            .cpu cortex-m0plus
            .thumb

            .section .boot2, "ax"
            \n
            """
        for bytes in checksummed.chunks(ofCount: 16) {
            let commaSeparatedHexBytes = bytes
                .map { byte in "0x\(byte.hex())" }
                .joined(separator: ", ")
            output.append(".byte \(commaSeparatedHexBytes)\n")
        }

        let outputURL = URL(fileURLWithPath: outputFile)
        try Data(output.utf8).write(to: outputURL)
    }
}

struct CLIError: Error {
    var message: String
}

extension Sequence {
    func chunks(ofCount chunkSize: Int) -> [[Element]] {
        precondition(chunkSize > 0, "Expected chunkSize > 0, actual value was \(chunkSize)")
        var result: [[Element]] = []
        var iterator = self.makeIterator()
        var currentChunk: [Element] = []
        while let element = iterator.next() {
            currentChunk.append(element)
            if currentChunk.count == chunkSize {
                result.append(currentChunk)
                currentChunk.removeAll(keepingCapacity: true)
            }
        }
        if !currentChunk.isEmpty {
            result.append(currentChunk)
        }
        return result
    }
}

extension UInt8 {
    func hex(uppercase: Bool = false) -> String {
        let hexString = String(self, radix: 16, uppercase: false)
        if self < 16 {
            return "0\(hexString)"
        } else {
            return hexString
        }
    }
}
