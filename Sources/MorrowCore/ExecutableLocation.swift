import Foundation
import Darwin

public enum ExecutableLocation {
    public static func current() throws -> URL {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        var bytes = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&bytes, &size) == 0 else {
            throw MorrowError.message("Could not locate Morrow's command launcher.")
        }
        return URL(fileURLWithPath: String(cString: bytes)).resolvingSymlinksInPath()
    }
}
