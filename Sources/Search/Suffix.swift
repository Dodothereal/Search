import Foundation

/// The public suffix list, as macOS keeps it.
///
/// "Public suffix" is the part of a name that nobody can call their own: a
/// top-level domain (`com`, `co.uk`) or a private one a service hands out
/// under (`github.io`, `blogspot.com`, `web.app`, `herokuapp.com`). What is
/// left of a host once its suffix is taken off is the registrable name — the
/// one thing two hosts share when they are the same site. `accounts.example.com`
/// and `example.com` both come down to `example.com`; `alice.github.io` and
/// `evil.github.io` do not come down to anything shared, because `github.io`
/// is the suffix and each name below it is its own site.
///
/// Why it matters here, twice: a password saved for one host is offered to
/// another only when they are the same site (Vault), and a page may only
/// claim a passkey for its own host or one above it (Passkeys). Get the
/// suffix wrong and the first hands a password to a stranger's page, and the
/// second lets a page claim a passkey that is not its own.
///
/// The list is not kept here: it is long, it changes, and macOS already ships
/// it. `_CFHostIsDomainTopLevel` is the function behind it — private to
/// CFNetwork, but asked for by name the way the Web Inspector flag is (see
/// Web.inspector). Where it cannot be found, `isSuffix` says no, and every
/// caller falls back to the safe answer rather than a whole host list of its
/// own: Vault matches the host exactly, and Passkeys accepts only the page's
/// own host.
enum PublicSuffix {
    /// True for `com`, `co.uk`, `github.io`; false for `example.com` and for
    /// `alice.github.io` — a name *under* a suffix is a site, not a suffix.
    static func isSuffix(_ name: String) -> Bool {
        guard let test = test else { return false }
        return test(name.lowercased() as CFString)
    }

    /// The registrable name of a host: its labels down to, but not including,
    /// its public suffix. `www.example.com` and `accounts.example.com` both
    /// answer `example.com`; `bbc.co.uk` answers `bbc.co.uk`.
    ///
    /// A host with nothing below its suffix (`github.io` itself), and a host
    /// whose suffix cannot be found at all, answer as they stand — never
    /// something shorter, which could only ever widen what counts as one site.
    /// An address answers as it stands too: an IPv4 literal is four numbers,
    /// not a name with a site behind it, and reading one as labels once made
    /// `192.168.1.5` and `10.0.1.5` the same site.
    static func registrable(_ host: String) -> String {
        let name = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !name.isEmpty, !isAddress(name) else { return name }
        let labels = name.split(separator: ".").map(String.init)
        // One label is a name of its own (localhost); two are a name and a
        // suffix (example.com); there is nothing to walk down to.
        guard labels.count > 2 else { return name }
        // The shortest prefix that is not itself a suffix. Walking from the
        // left is what makes the private ones work: `evil.github.io` has to
        // take `github.io` for its suffix, where taking a fixed last-two
        // labels would have taken `github.io` for the site instead.
        for end in 1...(labels.count - 1) {
            let candidate = labels[(labels.count - end)...].joined(separator: ".")
            if isSuffix(candidate) { continue }
            return candidate
        }
        return name
    }

    /// An IPv4 or IPv6 literal: nothing to split into a site and a suffix.
    private static func isAddress(_ host: String) -> Bool {
        if host.contains(":") { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }

    /// `_CFHostIsDomainTopLevel`, from the CFNetwork framework macOS ships.
    /// Asked for once; nil on a Mac that does not have it, which every caller
    /// above answers safely.
    private static let test: (@convention(c) (CFString) -> Bool)? = {
        guard let handle = dlopen("/System/Library/Frameworks/CFNetwork.framework/CFNetwork", RTLD_NOW),
              let symbol = dlsym(handle, "_CFHostIsDomainTopLevel")
        else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (CFString) -> Bool).self)
    }()
}
