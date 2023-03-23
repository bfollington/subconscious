//
//  AddressBookModel.swift
//  Subconscious (iOS)
//
//  Created by Ben Follington on 6/3/2023.
//

import os
import Foundation
import SwiftUI
import ObservableStore
import Combine

struct AddressBookEntry: Equatable {
    var pfp: Image
    var petname: Petname
    var did: Did
}

struct AddressBookEnvironment {
    var data: DataService
}


struct FollowUserFormModel: Equatable {
    var did: FormField<String, Did> = FormField(value: "", validate: Self.validateDid)
    var petname: FormField<String, Petname> = FormField(value: "", validate: Self.validatePetname)
    
    static func validateDid(key: String) -> Did? {
        Did(key)
    }

    static func validatePetname(petname: String) -> Petname? {
        Petname(petname)
    }
}

struct PetnameFieldCursor: CursorProtocol {
    static func get(state: AddressBookModel) -> FormField<String, Petname> {
        state.followUserForm.petname
    }
    
    static func set(state: AddressBookModel, inner: FormField<String, Petname>) -> AddressBookModel {
        var model = state
        model.followUserForm.petname = inner
        return model
    }
    
    static func tag(_ action: FormFieldAction<String>) -> AddressBookAction {
        AddressBookAction.petnameField(action)
    }
}

struct DidFieldCursor: CursorProtocol {
    static func get(state: AddressBookModel) -> FormField<String, Did> {
        state.followUserForm.did
    }
    
    static func set(state: AddressBookModel, inner: FormField<String, Did>) -> AddressBookModel {
        var model = state
        model.followUserForm.did = inner
        return model
    }
    
    static func tag(_ action: FormFieldAction<String>) -> AddressBookAction {
        AddressBookAction.didField(action)
    }
}

enum AddressBookAction {
    case present(_ isPresented: Bool)
    
    case refreshEntries(forceRefetchFromNoosphere: Bool = false)
    case populate([AddressBookEntry])
    
    case requestFollow
    case attemptFollow
    case failFollow(error: String)
    case dismissFailFollowError
    case succeedFollow(did: Did, petname: Petname)
    
    case requestUnfollow(petname: Petname)
    case confirmUnfollow
    case cancelUnfollow
    case failUnfollow(error: String)
    case dismissFailUnfollowError
    case succeedUnfollow(petname: Petname)
    
    case presentFollowUserForm(_ isPresented: Bool)
    case didField(FormFieldAction<String>)
    case petnameField(FormFieldAction<String>)

    case presentQRCodeScanner(_ isPresented: Bool)
    case qrCodeScanned(scannedContent: String)
    case qrCodeScanError(error: String)
}

struct AddressBookModel: ModelProtocol {
    var isPresented = false
    var did: Did? = nil
    var follows: [AddressBookEntry] = []
    
    var isFollowUserFormPresented = false
    var followUserForm = FollowUserFormModel()
    
    var failFollowErrorMessage: String? = nil
    var failUnfollowErrorMessage: String? = nil
    var failQRCodeScanErrorMessage: String? = nil
    
    var unfollowCandidate: Petname? = nil
    
    var isQrCodeScannerPresented = false

    static let logger = Logger(
        subsystem: Config.default.rdns,
        category: "AddressBookModel"
    )

    static func update(
        state: AddressBookModel,
        action: AddressBookAction,
        environment: AddressBookEnvironment
    ) -> Update<AddressBookModel> {
        switch action {
            
        case .present(let isPresented):
            var model = state
            model.isPresented = isPresented
            model.failUnfollowErrorMessage = nil
            model.failFollowErrorMessage = nil
            
            if isPresented {
                do {
                    model.did = try Did(environment.data.noosphere.identity())
                } catch {
                    model.did = nil
                }
            }
            
            return update(
                state: model,
                action: .refreshEntries(forceRefetchFromNoosphere: false),
                environment: environment
            )
            
        case .refreshEntries(let forceRefreshFromNoosphere):
            let fx: Fx<AddressBookAction> =
                environment.data.addressBook.listEntries(refetch: forceRefreshFromNoosphere)
                .map({ follows in
                    AddressBookAction.populate(follows)
                })
                .eraseToAnyPublisher()
            
            return Update(state: state, fx: fx)
            
        case .populate(let follows):
            var model = state
            model.follows = follows
            return Update(state: model)
            
        case .presentFollowUserForm(let isPresented):
            var model = state
            
            model.failFollowErrorMessage = nil
            model.isFollowUserFormPresented = isPresented
            
            return update(
                state: model,
                actions: [
                    .didField(.reset),
                    .petnameField(.reset)
                ],
                environment: environment
            )
            
        case .didField(let action):
            return DidFieldCursor.update(
                state: state,
                action: action,
                environment: FormFieldEnvironment()
            )
            
        case .petnameField(let action):
            return PetnameFieldCursor.update(
                state: state,
                action: action,
                environment: FormFieldEnvironment()
            )
            
        case .requestFollow:
            return update(
                state: state,
                actions: [
                    // Show errors on any untouched fields, hints at why you cannot submit
                    .didField(.markAsTouched),
                    .petnameField(.markAsTouched),
                    .attemptFollow
                ],
                environment: environment
            )

            
        case .attemptFollow:
            guard let did = state.followUserForm.did.validated else {
                return Update(state: state)
            }
            guard let petname = state.followUserForm.petname.validated else {
                return Update(state: state)
            }
            
            guard !state.follows.contains(where: { f in f.did == did }) else {
                return update(
                    state: state,
                    action: .failFollow(error: "Already following user"),
                    environment: environment
                )
            }
            
            let fx: Fx<AddressBookAction> =
                environment.data.addressBook
                .followUserAsync(did: did, petname: petname)
                .map({ _ in
                    AddressBookAction.succeedFollow(did: did, petname: petname)
                })
                .catch({ error in
                    Just(
                        AddressBookAction.failFollow(error: error.localizedDescription)
                    )
                })
                .eraseToAnyPublisher()
            
            return Update(state: state, fx: fx)
            
        case .succeedFollow(did: let did, petname: let petname):
            let entry = AddressBookEntry(pfp: Image("sub_logo_dark"), petname: petname, did: did)
            
            var model = state
            model.isFollowUserFormPresented = false
            model.follows.append(entry)
            
            return update(
                state: model,
                action: .refreshEntries(forceRefetchFromNoosphere: true),
                environment: environment
            )
            
        case .failFollow(error: let error):
            var model = state
            model.failFollowErrorMessage = error
            return Update(state: model)
            
        case .dismissFailFollowError:
            var model = state
            model.failFollowErrorMessage = nil
            return Update(state: model)
            
        case .requestUnfollow(petname: let petname):
            var model = state
            model.unfollowCandidate = petname
            return Update(state: model)
            
        case .cancelUnfollow:
            var model = state
            model.unfollowCandidate = nil
            return Update(state: model)
            
        case .confirmUnfollow:
            guard let petname = state.unfollowCandidate else {
                return Update(state: state)
            }
            
            let fx: Fx<AddressBookAction> =
                environment.data.addressBook
                .unfollowUserAsync(petname: petname)
                .map({ _ in
                    AddressBookAction.succeedUnfollow(petname: petname)
                })
                .catch({ error in
                    Just(
                        AddressBookAction.failUnfollow(error: error.localizedDescription)
                    )
                })
                .eraseToAnyPublisher()
            
            return Update(state: state, fx: fx)
            
        case .succeedUnfollow(let petname):
            var model = state
            model.follows.removeAll { f in
                f.petname == petname
            }
            return update(
                state: model,
                action: .refreshEntries(forceRefetchFromNoosphere: true),
                environment: environment
            )
            
        case .failUnfollow(error: let error):
            var model = state
            model.failUnfollowErrorMessage = error
            return Update(state: model)
            
        case .dismissFailUnfollowError:
            var model = state
            model.failUnfollowErrorMessage = nil
            return Update(state: model)
        
        case .presentQRCodeScanner(let isPresented):
            var model = state
            model.failQRCodeScanErrorMessage = nil
            model.isQrCodeScannerPresented = isPresented
            return Update(state: model)
        
        case .qrCodeScanned(scannedContent: let content):
            return update(
                state: state,
                actions: [
                    .didField(.markAsTouched),
                    .didField(.setValue(input: content))
                ],
                environment: environment
            )
            
        case .qrCodeScanError(error: let error):
            var model = state
            model.failQRCodeScanErrorMessage = error
            return Update(state: model)
            
        }
        
    }
}