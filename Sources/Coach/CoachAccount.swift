import AuthenticationServices
import Foundation
import Observation
import StoreKit

/// Sign in with Apple session for the Coach proxy plus the Coach subscription (StoreKit 2).
@Observable
@MainActor
final class CoachAccount {
    static let productID = "com.alan.autopiloto.coach.monthly"

    private(set) var sessionToken: String? = APIKeyStore.load(APIKeyStore.coachSession)
    private(set) var appleUserID: String? = APIKeyStore.load(APIKeyStore.appleUser)
    private(set) var isSubscribed = false
    private(set) var product: Product?
    private(set) var lastError: String?
    /// Debug-only: `AUTOPILOTO_SCREENSHOT=paywall` shows the subscribe screen without StoreKit
    /// (App Store review screenshots are taken from the simulator via `simctl`, which cannot
    /// attach the .storekit configuration).
    static let screenshotMode = ProcessInfo.processInfo.environment["AUTOPILOTO_SCREENSHOT"]
    var previewPrice: String? {
        #if DEBUG
        Self.screenshotMode == "paywall" && product == nil ? "$4.99" : nil
        #else
        nil
        #endif
    }

    var isSignedIn: Bool { sessionToken != nil }

    private var updates: Task<Void, Never>?

    init() {
        #if DEBUG
        if Self.screenshotMode == "paywall" {
            sessionToken = "preview"
            isSubscribed = false
        }
        #endif
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refreshEntitlement()
            }
        }
    }

    // MARK: - Sign in with Apple

    /// Call from `SignInWithAppleButton`'s completion with the authorization result.
    func handleSignIn(_ result: Result<ASAuthorization, Error>, proxy: URL) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled { lastError = error.localizedDescription }
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken, let identityToken = String(data: data, encoding: .utf8) else {
                lastError = "Apple returned no identity token."
                return
            }
            do {
                let token = try await CoachClient.openSession(base: proxy, identityToken: identityToken)
                APIKeyStore.save(token, account: APIKeyStore.coachSession)
                APIKeyStore.save(credential.user, account: APIKeyStore.appleUser)
                sessionToken = token
                appleUserID = credential.user
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func signOut() {
        APIKeyStore.delete(APIKeyStore.coachSession)
        APIKeyStore.delete(APIKeyStore.appleUser)
        sessionToken = nil
        appleUserID = nil
    }

    /// A 401 from the proxy means the 30-day session expired: drop it so the button comes back.
    func sessionRejected() {
        signOut()
    }

    // MARK: - Subscription

    func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            lastError = error.localizedDescription
        }
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.productID, t.revocationDate == nil {
                active = true
            }
        }
        isSubscribed = active
    }

    func purchase() async {
        guard let product else { return }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let t) = verification { await t.finish() }
                await refreshEntitlement()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }
}
