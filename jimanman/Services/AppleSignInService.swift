import AuthenticationServices
import UIKit

struct AppleSignInCredential {
    let identityToken: String
    let authorizationCode: String?
    let userIdentifier: String
    let email: String?
    let givenName: String?
    let familyName: String?
}

enum AppleSignInError: LocalizedError {
    case missingCredential
    case missingIdentityToken
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "Apple 登录凭证无效"
        case .missingIdentityToken:
            return "Apple 登录令牌无效"
        case .cancelled:
            return "已取消 Apple 登录"
        }
    }
}

final class AppleSignInService: NSObject {
    static let shared = AppleSignInService()

    private var completion: ((Result<AppleSignInCredential, Error>) -> Void)?

    private override init() {
        super.init()
    }

    func signIn(completion: @escaping (Result<AppleSignInCredential, Error>) -> Void) {
        self.completion = completion

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func cancel() {
        completion = nil
    }
}

extension AppleSignInService: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            DispatchQueue.main.async {
                self.completion?(.failure(AppleSignInError.missingCredential))
                self.completion = nil
            }
            return
        }

        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8),
              !identityToken.isEmpty else {
            DispatchQueue.main.async {
                self.completion?(.failure(AppleSignInError.missingIdentityToken))
                self.completion = nil
            }
            return
        }

        let authCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        let result = AppleSignInCredential(
            identityToken: identityToken,
            authorizationCode: authCode,
            userIdentifier: credential.user,
            email: credential.email,
            givenName: credential.fullName?.givenName,
            familyName: credential.fullName?.familyName
        )
        DispatchQueue.main.async {
            self.completion?(.success(result))
            self.completion = nil
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        let callback = completion
        completion = nil
        DispatchQueue.main.async {
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                callback?(.failure(AppleSignInError.cancelled))
            } else {
                callback?(.failure(error))
            }
        }
    }
}

extension AppleSignInService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        return window ?? ASPresentationAnchor()
    }
}
