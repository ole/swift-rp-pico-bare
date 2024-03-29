import MMIOVolatile

// SIO = the RP2040’s single-cycle I/O block.
// Reference documentation: https://datasheets.raspberrypi.com/rp2040/rp2040-datasheet.pdf#tab-registerlist_sio
let SIO_BASE: UInt32 = 0xd0000000
let SIO_GPIO_IN_OFFSET: UInt32 = 0x00000004
let SIO_GPIO_OUT_SET_OFFSET: UInt32 = 0x00000014
let SIO_GPIO_OUT_CLR_OFFSET: UInt32 = 0x00000018
let SIO_GPIO_OUT_ENABLE_SET_OFFSET: UInt32 = 0x00000024
let SIO_GPIO_OUT_ENABLE_CLR_OFFSET: UInt32 = 0x00000028

// Reference to datasheet: https://datasheets.raspberrypi.com/rp2040/rp2040-datasheet.pdf#tab-registerlist_pads_bank0
let PADS_BANK0_BASE: UInt32 = 0x4001c000
let PADS_BANK0_GPIO0_OFFSET: UInt32 = 0x00000004
let PADS_BANK0_GPIO0_BITS: UInt32 = 0x000000ff
let PADS_BANK0_GPIO0_RESET: UInt32 = 0x00000056
let PADS_BANK0_GPIO0_IE_BITS: UInt32 = 0x00000040
let PADS_BANK0_GPIO0_OD_BITS: UInt32 = 0x00000080
let PADS_BANK0_GPIO0_PUE_BITS: UInt32 = 0x00000008
let PADS_BANK0_GPIO0_PUE_LSB: UInt32 = 3
let PADS_BANK0_GPIO0_PDE_BITS: UInt32 = 0x00000004
let PADS_BANK0_GPIO0_PDE_LSB: UInt32 = 2

let IO_BANK0_BASE: UInt32 = 0x40014000
let IO_BANK0_GPIO0_CTRL_OFFSET: UInt32 = 0x00000004
let IO_BANK0_GPIO0_CTRL_FUNCSEL_LSB = 0

// Register address offsets for atomic RMW aliases
let REG_ALIAS_RW_BITS: UInt32 = 0x0000
let REG_ALIAS_XOR_BITS: UInt32 = 0x1000
let REG_ALIAS_SET_BITS: UInt32 = 0x2000
let REG_ALIAS_CLR_BITS: UInt32 = 0x3000

public func gpioInit(pin: Int) {
    gpioSetDirection(pin: pin, out: true)
    gpioSet(pin: pin, high: false)
    gpioSetFunction(pin: pin, .SIO)
}

public enum GPIOFunction: Int {
    case XIP = 0
    case SPI = 1
    case UART = 2
    case I2C = 3
    case PWM = 4
    case SIO = 5
    case PIO0 = 6
    case PIO1 = 7
    case GPCK = 8
    case USB = 9
    case NULL = 0x1f
}

/// Select function for this GPIO, and ensure input/output are enabled at the pad.
/// This also clears the input/output/irq override bits.
public func gpioSetFunction(pin: Int, _ function: GPIOFunction) {
    // Set input enable on, output disable off
    let padsBank = UnsafeMutablePointer<UInt32>(bitPattern: UInt(PADS_BANK0_BASE) + UInt(PADS_BANK0_GPIO0_OFFSET) + (UInt(pin) * UInt(MemoryLayout<UInt32>.stride)))!
    hwWriteMasked(
        address: padsBank, 
        values: PADS_BANK0_GPIO0_IE_BITS, 
        mask: PADS_BANK0_GPIO0_IE_BITS | PADS_BANK0_GPIO0_OD_BITS
    )
    // Zero all fields apart from fsel; we want this IO to do what the peripheral tells it.
    // This doesn't affect e.g. pullup/pulldown, as these are in pad controls.
    let controlReg = UnsafeMutablePointer<UInt32>(bitPattern: UInt(IO_BANK0_BASE) + UInt(pin * 2 * MemoryLayout<UInt32>.stride) + UInt(IO_BANK0_GPIO0_CTRL_OFFSET))!
    mmio_volatile_store_uint32_t(controlReg, UInt32(function.rawValue) << IO_BANK0_GPIO0_CTRL_FUNCSEL_LSB)
}

public func gpioSetDirection(pin: Int, out: Bool) {
    let mask: UInt32 = 1 << pin
    if out {
        gpioSetDirectionOutMasked(mask: mask)
    } else {
        gpioSetDirectionInMasked(mask: mask)
    }
}

func gpioSetDirectionOutMasked(mask: UInt32) {
    // sio_hw->gpio_oe_set = mask;
    let ptr = UnsafeMutablePointer<UInt32>(bitPattern: UInt(SIO_BASE + SIO_GPIO_OUT_ENABLE_SET_OFFSET))!
    mmio_volatile_store_uint32_t(ptr, mask)
}

func gpioSetDirectionInMasked(mask: UInt32) {
    // sio_hw->gpio_oe_clr = mask;
    let ptr = UnsafeMutablePointer<UInt32>(bitPattern: UInt(SIO_BASE + SIO_GPIO_OUT_ENABLE_CLR_OFFSET))!
    mmio_volatile_store_uint32_t(ptr, mask)
}

/// Set the specified GPIO to be pulled up.
public func gpioPullUp(pin: Int) {
    gpioSetPulls(pin: pin, up: true, down: false)
}

public func gpioPullDown(pin: Int) {
    gpioSetPulls(pin: pin, up: false, down: true)
}

/// Select up and down pulls on specific GPIO.
///
/// On RP2040, setting both pulls enables a "bus keep" function,
/// i.e. weak pull to whatever is current high/low state of GPIO.
public func gpioSetPulls(pin: Int, up: Bool, down: Bool) {
    let padsBank = UnsafeMutablePointer<UInt32>(bitPattern: UInt(PADS_BANK0_BASE) + UInt(PADS_BANK0_GPIO0_OFFSET) + (UInt(pin) * UInt(MemoryLayout<UInt32>.stride)))!
    let value: UInt32 = (up ? 1 : 0) << PADS_BANK0_GPIO0_PUE_LSB
        | (down ? 1 : 0) << PADS_BANK0_GPIO0_PDE_LSB
    let mask = PADS_BANK0_GPIO0_PUE_BITS | PADS_BANK0_GPIO0_PDE_BITS
    hwWriteMasked(address: padsBank, values: value, mask: mask)
}

// Get the value of a single GPIO
public func gpioGet(pin: Int) -> Bool {
    let mask: UInt32 = 1 << pin
    // sio_hw->gpio_in
    let ptr = UnsafeMutablePointer<UInt32>(bitPattern: UInt(SIO_BASE + SIO_GPIO_IN_OFFSET))!
    let gpioIn = mmio_volatile_load_uint32_t(ptr)
    let isOn = (gpioIn & mask) != 0
    return isOn
}

public func gpioSet(pin: Int, high: Bool) {
    let mask: UInt32 = 1 << pin
    if high {
        gpioSetMasked(mask: mask)
    } else {
        gpioClearMasked(mask: mask)
    }
}

func gpioSetMasked(mask: UInt32) {
    // sio_hw->gpio_set = mask;
    let ptr = UnsafeMutablePointer<UInt32>(bitPattern: UInt(SIO_BASE + SIO_GPIO_OUT_SET_OFFSET))!
    mmio_volatile_store_uint32_t(ptr, mask)
}

func gpioClearMasked(mask: UInt32) {
    // sio_hw->gpio_clr = mask;
    let ptr = UnsafeMutablePointer<UInt32>(bitPattern: UInt(SIO_BASE + SIO_GPIO_OUT_CLR_OFFSET))!
    mmio_volatile_store_uint32_t(ptr, mask)
}
