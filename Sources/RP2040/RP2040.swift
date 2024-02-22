@_exported import MMIOVolatile

/// Set new values for a sub-set of the bits in a HW register.
/// 
/// Sets destination bits to values specified in \p values, if and only if corresponding bit in \p write_mask is set.
func hwWriteMasked(address: UnsafeMutablePointer<UInt32>, values: UInt32, mask writeMask: UInt32) {
    hwXORBits(address: address, mask: (address.pointee ^ values) & writeMask)
}

func hwXORBits(address: UnsafeMutablePointer<UInt32>, mask: UInt32) {
    let rawPtr = UnsafeMutableRawPointer(address).advanced(by: Int(REG_ALIAS_XOR_BITS))
    let ptr = rawPtr.assumingMemoryBound(to: UInt32.self)
    mmio_volatile_store_uint32_t(ptr, mask)
}

func hwSetBits(address: UnsafeMutablePointer<UInt32>, mask: UInt32) {
    let rawPtr = UnsafeMutableRawPointer(address).advanced(by: Int(REG_ALIAS_SET_BITS))
    let ptr = rawPtr.assumingMemoryBound(to: UInt32.self)
    mmio_volatile_store_uint32_t(ptr, mask)
}

func hwClearBits(address: UnsafeMutablePointer<UInt32>, mask: UInt32) {
    let rawPtr = UnsafeMutableRawPointer(address).advanced(by: Int(REG_ALIAS_CLR_BITS))
    let ptr = rawPtr.assumingMemoryBound(to: UInt32.self)
    mmio_volatile_store_uint32_t(ptr, mask)
}
