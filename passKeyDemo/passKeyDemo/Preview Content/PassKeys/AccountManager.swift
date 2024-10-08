//
//  AccountManager.swift
//  passKeyDemo
//
//  Created by Vijaykrishna Jonnalagadda on 19/09/24.
//
import AuthenticationServices
import Foundation
import CryptoKit
import os

extension NSNotification.Name {
    static let UserSignedIn = Notification.Name("UserSignedInNotification")
    static let ModalSignInSheetCanceled = Notification.Name("ModalSignInSheetCanceledNotification")
}

class AccountManager: NSObject, ASAuthorizationControllerPresentationContextProviding, ASAuthorizationControllerDelegate {
    let domain = "webcredentials:developerinsider.github.io"
    var authenticationAnchor: ASPresentationAnchor?
    var isPerformingModalReqest = false

    func signInWith(anchor: ASPresentationAnchor, preferImmediatelyAvailableCredentials: Bool) {
        self.authenticationAnchor = anchor
        let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: domain)

        // Fetch the challenge from the server. The challenge needs to be unique for each request.
        let challenge = Data()

        let assertionRequest = publicKeyCredentialProvider.createCredentialAssertionRequest(challenge: challenge)

        // Also allow the user to use a saved password, if they have one.
        let passwordCredentialProvider = ASAuthorizationPasswordProvider()
        let passwordRequest = passwordCredentialProvider.createRequest()

        // Pass in any mix of supported sign-in request types.
        let authController = ASAuthorizationController(authorizationRequests: [ assertionRequest, passwordRequest ] )
        authController.delegate = self
        authController.presentationContextProvider = self

        if preferImmediatelyAvailableCredentials {
            // If credentials are available, presents a modal sign-in sheet.
            // If there are no locally saved credentials, no UI appears and
            // the system passes ASAuthorizationError.Code.canceled to call
            // `AccountManager.authorizationController(controller:didCompleteWithError:)`.
            authController.performRequests(options: .preferImmediatelyAvailableCredentials)
        } else {
            // If credentials are available, presents a modal sign-in sheet.
            // If there are no locally saved credentials, the system presents a QR code to allow signing in with a
            // passkey from a nearby device.
            authController.performRequests()
        }

        isPerformingModalReqest = true
    }

    func beginAutoFillAssistedPasskeySignIn(anchor: ASPresentationAnchor) {
        self.authenticationAnchor = anchor

        let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: domain)

        // Fetch the challenge from the server. The challenge needs to be unique for each request.
        let challenge = Data()
        let assertionRequest = publicKeyCredentialProvider.createCredentialAssertionRequest(challenge: challenge)

        // AutoFill-assisted requests only support ASAuthorizationPlatformPublicKeyCredentialAssertionRequest.
        let authController = ASAuthorizationController(authorizationRequests: [ assertionRequest ] )
        authController.delegate = self
        authController.presentationContextProvider = self
        authController.performAutoFillAssistedRequests()
    }
    
    func signUpWith(userName: String, anchor: ASPresentationAnchor) {
        self.authenticationAnchor = anchor
        let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: domain)

        // Fetch the challenge from the server. The challenge needs to be unique for each request.
        // The userID is the identifier for the user's account.
        let challenge = Data()
        let userID = Data(UUID().uuidString.utf8)

        let registrationRequest = publicKeyCredentialProvider.createCredentialRegistrationRequest(challenge: challenge,
                                                                                                  name: userName, userID: userID)

        // Use only ASAuthorizationPlatformPublicKeyCredentialRegistrationRequests or
        // ASAuthorizationSecurityKeyPublicKeyCredentialRegistrationRequests here.
        let authController = ASAuthorizationController(authorizationRequests: [ registrationRequest ] )
        authController.delegate = self
        authController.presentationContextProvider = self
        authController.performRequests()
        isPerformingModalReqest = true
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let logger = Logger()
        switch authorization.credential {
        case let credentialRegistration as ASAuthorizationPlatformPublicKeyCredentialRegistration:
            logger.log("A new passkey was registered: \(credentialRegistration)")
            // Verify the attestationObject and clientDataJSON with your service.
            // The attestationObject contains the user's new public key to store and use for subsequent sign-ins.
             let attestationObject = credentialRegistration.rawAttestationObject
             let clientDataJSON = credentialRegistration.rawClientDataJSON
            
//            let publickey = attestationObject.map(\.authData)
            
            if let attestationData = attestationObject{
                if let publicKey = extractPublicKey(from: attestationData) {
                    print("Public key extracted successfully")
                    // Use the publicKey as needed
                    print("Public Key is :\(publicKey)")
                    
                } else {
                    print("Failed to extract public key")
                }
            }

            // After the server verifies the registration and creates the user account, sign in the user with the new account.
            didFinishSignIn()
        case let credentialAssertion as ASAuthorizationPlatformPublicKeyCredentialAssertion:
            logger.log("A passkey was used to sign in: \(credentialAssertion)")
            // Verify the below signature and clientDataJSON with your service for the given userID.
             let signature = credentialAssertion.signature
             let clientDataJSON = credentialAssertion.rawClientDataJSON
             let userID = credentialAssertion.userID
            print("signature is :\(signature),clientDataJSON is :\(clientDataJSON),userID is :\(userID)")
            // After the server verifies the assertion, sign in the user.
            didFinishSignIn()
        case let passwordCredential as ASPasswordCredential:
            logger.log("A password was provided: \(passwordCredential)")
            // Verify the userName and password with your service.
             let userName = passwordCredential.user
             let password = passwordCredential.password
            print("User Name is :\(userName),Password is :\(password)")
            // After the server verifies the userName and password, sign in the user.
            didFinishSignIn()
        default:
            fatalError("Received unknown authorization type.")
        }

        isPerformingModalReqest = false
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let logger = Logger()
        guard let authorizationError = error as? ASAuthorizationError else {
            isPerformingModalReqest = false
            logger.error("Unexpected authorization error: \(error.localizedDescription)")
            return
        }

        if authorizationError.code == .canceled {
            // Either the system doesn't find any credentials and the request ends silently, or the user cancels the request.
            // This is a good time to show a traditional login form, or ask the user to create an account.
            logger.log("Request canceled.")

            if isPerformingModalReqest {
                didCancelModalSheet()
            }
        } else {
            // Another ASAuthorization error.
            // Note: The userInfo dictionary contains useful information.
            logger.error("Error: \((error as NSError).userInfo)")
        }

        isPerformingModalReqest = false
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return authenticationAnchor!
    }

    func didFinishSignIn() {
        NotificationCenter.default.post(name: .UserSignedIn, object: nil)
    }

    func didCancelModalSheet() {
        NotificationCenter.default.post(name: .ModalSignInSheetCanceled, object: nil)
    }
    
    
    
    
    
   

    // Function to parse the attestation object and extract the public key
    func extractPublicKey(from attestationObject: Data) -> SecKey? {
        // Step 1: Parse the attestation object
        guard let json = try? JSONSerialization.jsonObject(with: attestationObject, options: []) as? [String: Any],
              let authDataBase64 = json["authData"] as? String,
              let authData = Data(base64Encoded: authDataBase64) else {
            print("Failed to parse attestation object")
            return nil
        }
        // Step 2: Extract the public key from authData
        // This example assumes the key is in the COSE format
        let coseKey = extractCOSEKey(from: authData)
        
        // Step 3: Convert COSE key to SecKey
        let publicKey = createSecKey(from: coseKey)
        
        return publicKey
    }

    // Helper function to extract COSE key (this is a simplified example)
    func extractCOSEKey(from authData: Data) -> [UInt8] {
        // Implement parsing logic here based on your specific COSE structure
        // This is just a placeholder
        return [UInt8]() // Return the appropriate byte array representing the key
    }

    // Helper function to create a SecKey from COSE key (simplified)
    func createSecKey(from coseKey: [UInt8]) -> SecKey? {
        let keyData = Data(coseKey)
        
        // Define key attributes
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeEC,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 256 // Adjust based on your key size
        ]
        
        var error: Unmanaged<CFError>?
        let secKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error)
        
        if let error = error?.takeRetainedValue() {
            print("Error creating SecKey: \(error.localizedDescription)")
            return nil
        }
        
        return secKey
    }

    // Example usage
   

}

