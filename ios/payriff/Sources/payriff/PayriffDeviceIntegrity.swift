import Darwin
import Foundation
import MachO

/// What the device integrity checks read (CONTRACT §16.16). Each answers `false`, empty or nil
/// when it cannot tell.
protocol PayriffIntegrityProbes {
  /// The iOS simulator, whose file system is the Mac's.
  var isSimulator: Bool { get }

  /// Whether the app bundle has an `embedded.mobileprovision`: development, ad hoc and
  /// enterprise builds do; App Store and TestFlight builds do not.
  var hasEmbeddedProvisioningProfile: Bool { get }

  func fileExists(_ path: String) -> Bool

  /// Writes a file at `path` outside the sandbox and removes it again; true when that worked.
  func canWriteFile(atPath path: String) -> Bool

  /// The paths of the images (libraries) loaded into this process.
  func loadedImages() -> [String]

  func environmentValue(_ name: String) -> String?

  /// Whether something accepts a TCP connection on 127.0.0.1:`port` within `timeout`.
  func acceptsLoopbackConnection(port: UInt16, timeout: TimeInterval) -> Bool

  /// Whether a debugger traces this process (`P_TRACED`).
  func isTraced() -> Bool
}

/// Jailbreak, hooking and debugger checks for `deviceIntegrity` (CONTRACT §16.16). The decisions
/// are pure Swift behind `PayriffIntegrityProbes`; `PayriffDeviceProbes` reads the device.
///
/// The jailbreak file and sandbox checks run once per instance: a device is not jailbroken while
/// the app runs. The hooking, Frida and debugger checks run at every call, because such a tool can
/// attach at any time. `DYLD_INSERT_LIBRARIES` and a debugger count only in App Store and
/// TestFlight builds: when Xcode runs a development build, it sets the variable for its
/// diagnostics and attaches its debugger. Nothing is checked on the simulator. The checks are local
/// and can be bypassed; they stop the common tools.
final class PayriffDeviceIntegrity {
  static let jailbreakFiles = [
    "/Applications/Cydia.app",
    "/Applications/Sileo.app",
    "/Applications/Zebra.app",
    "/Applications/Filza.app",
    "/Library/MobileSubstrate/MobileSubstrate.dylib",
    "/usr/sbin/sshd",
    "/usr/bin/sshd",
    "/usr/libexec/sftp-server",
    "/etc/apt",
    "/private/var/lib/apt/",
    "/private/var/lib/cydia",
    "/private/var/stash",
    "/var/jb",
    "/private/preboot/jb",
    "/usr/lib/TweakInject",
    "/usr/lib/libhooker.dylib",
    "/usr/lib/libsubstitute.dylib",
    "/.bootstrapped",
    "/.installed_unc0ver",
    "/bin/bash",
  ]

  /// Written and removed at once; only a jailbreak lets an app write there.
  static let sandboxProbePath = "/private/payriff-jb-check"

  /// Parts of the path of a hooking library, compared without regard to case.
  static let hookingImages = [
    "MobileSubstrate", "SubstrateLoader", "TweakInject", "libhooker", "substitute", "ellekit",
    "systemhook", "SSLKillSwitch", "FridaGadget", "frida", "cynject", "libcycript",
  ]

  static let fridaServerPort: UInt16 = 27042
  static let fridaServerTimeout: TimeInterval = 0.1

  static let jailbreakFilesSignal = "jailbreak files"
  static let sandboxWriteSignal = "sandbox write"
  static let hookingLibrarySignal = "hooking library"
  static let fridaSignal = "Frida"
  static let insertedLibrariesSignal = "DYLD_INSERT_LIBRARIES"
  static let fridaServerSignal = "frida-server"
  static let debuggerSignal = "debugger"

  private let probes: PayriffIntegrityProbes
  private let lock = NSLock()
  private var jailbreakSignals: [String]?

  init(probes: PayriffIntegrityProbes) {
    self.probes = probes
  }

  /// The names of the signals that match now, for example `Frida`; empty when none does.
  func signals() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    if probes.isSimulator { return [] }
    let jailbreak = jailbreakSignals ?? jailbreakChecks()
    jailbreakSignals = jailbreak
    var seen = Set<String>()
    return (jailbreak + hookingChecks() + debuggerChecks()).filter { seen.insert($0).inserted }
  }

  private func jailbreakChecks() -> [String] {
    var signals: [String] = []
    if Self.jailbreakFiles.contains(where: probes.fileExists) {
      signals.append(Self.jailbreakFilesSignal)
    }
    if probes.canWriteFile(atPath: Self.sandboxProbePath) {
      signals.append(Self.sandboxWriteSignal)
    }
    return signals
  }

  private func hookingChecks() -> [String] {
    var signals: [String] = []
    let parts = Self.hookingImages.map { $0.lowercased() }
    for image in probes.loadedImages().map({ $0.lowercased() }) {
      guard let part = parts.first(where: { image.contains($0) }) else { continue }
      let signal = part.contains("frida") ? Self.fridaSignal : Self.hookingLibrarySignal
      if !signals.contains(signal) { signals.append(signal) }
    }
    // Only in App Store and TestFlight builds: Xcode sets it for its diagnostics (such as the Main
    // Thread Checker) when it runs a development build.
    if !probes.hasEmbeddedProvisioningProfile,
      let inserted = probes.environmentValue("DYLD_INSERT_LIBRARIES"), !inserted.isEmpty
    {
      signals.append(Self.insertedLibrariesSignal)
    }
    if probes.acceptsLoopbackConnection(port: Self.fridaServerPort, timeout: Self.fridaServerTimeout) {
      signals.append(Self.fridaServerSignal)
    }
    return signals
  }

  /// A debugger counts only in App Store and TestFlight builds, so development from Xcode is not
  /// blocked.
  private func debuggerChecks() -> [String] {
    guard !probes.hasEmbeddedProvisioningProfile, probes.isTraced() else { return [] }
    return [Self.debuggerSignal]
  }
}

/// The device side of `PayriffIntegrityProbes`. It reads names and flags only; file contents never
/// leave it. Blocking: call it off the main thread.
struct PayriffDeviceProbes: PayriffIntegrityProbes {
  var isSimulator: Bool {
    #if targetEnvironment(simulator)
      return true
    #else
      return false
    #endif
  }

  var hasEmbeddedProvisioningProfile: Bool {
    Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil
  }

  func fileExists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
  }

  func canWriteFile(atPath path: String) -> Bool {
    guard FileManager.default.createFile(atPath: path, contents: Data("x".utf8)) else {
      return false
    }
    try? FileManager.default.removeItem(atPath: path)
    return true
  }

  func loadedImages() -> [String] {
    (0..<_dyld_image_count()).compactMap { index in
      _dyld_get_image_name(index).map { String(cString: $0) }
    }
  }

  func environmentValue(_ name: String) -> String? {
    getenv(name).map { String(cString: $0) }
  }

  func acceptsLoopbackConnection(port: UInt16, timeout: TimeInterval) -> Bool {
    let socketDescriptor = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    guard socketDescriptor >= 0 else { return false }
    defer { close(socketDescriptor) }
    let flags = fcntl(socketDescriptor, F_GETFL, 0)
    guard flags >= 0, fcntl(socketDescriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
      return false
    }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let connected = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    if connected == 0 { return true }
    guard errno == EINPROGRESS else { return false }
    var poller = pollfd(fd: socketDescriptor, events: Int16(POLLOUT), revents: 0)
    guard poll(&poller, 1, Int32(timeout * 1000)) == 1 else { return false }
    var socketError: Int32 = 0
    var length = socklen_t(MemoryLayout<Int32>.size)
    guard getsockopt(socketDescriptor, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0 else {
      return false
    }
    return socketError == 0
  }

  func isTraced() -> Bool {
    var info = kinfo_proc()
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    var size = MemoryLayout<kinfo_proc>.stride
    guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return false }
    return (info.kp_proc.p_flag & P_TRACED) != 0
  }
}
