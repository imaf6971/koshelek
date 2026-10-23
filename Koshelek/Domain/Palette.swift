import Foundation

/// Muted earthy palette shared by the iPhone and Watch apps: (light, dark) RGB values per key.
enum PaletteTable {
    static let entries: [(key: String, light: UInt32, dark: UInt32)] = [
        ("clay", 0xD97757, 0xE08B6D), ("sand", 0xC2AA7A, 0xD4C29C), ("olive", 0x7D8450, 0x9AA169),
        ("slate", 0x5E7A94, 0x7F9BB5), ("rose", 0xB87A86, 0xCC939E), ("ochre", 0xC8963E, 0xD9AB57),
        ("sage", 0x7FA08C, 0xA3C0AF), ("plum", 0x8A6A8E, 0xA486A8), ("teal", 0x4F8A8B, 0x6FA6A7),
        ("stone", 0x8C8A82, 0xA8A69E), ("brick", 0xA5524A, 0xC06E65), ("moss", 0x5F7F52, 0x8FB07F),
    ]
}
