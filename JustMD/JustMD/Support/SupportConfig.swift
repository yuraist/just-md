import Foundation

/// Public configuration for the Support window. The Supabase key is the
/// publishable (anon) key: it only grants what row-level security allows,
/// which for this app is inserting one newsletter row.
nonisolated enum SupportConfig {
    static let supabaseURL = URL(string: "https://txeisrdkgcloqjiqexnw.supabase.co")!
    static let supabasePublishableKey = "sb_publishable_NQwid8YDTkIdshoUa9lNVQ_Hm3U5QQE"
    static let newsletterSource = "justmd-mac"
    static let coffeeProductID = "com.nuta.JustMD.coffee"
}
