func crc32(
    message: some Sequence<UInt8>,
    polynomial: UInt32,
    initialValue: UInt32 = 0xffff_ffff,
    xorOut: UInt32 = 0xffff_ffff
) -> UInt32 {
    var crc = initialValue
    for byte in message {
        crc ^= UInt32(byte) << 24;
        for _ in 0..<8 {
            let isTopmostBitSet = crc & (1 << 31) != 0
            crc <<= 1
            if isTopmostBitSet {
                crc ^= polynomial
            }
        }
    }
    return crc ^ xorOut
}
