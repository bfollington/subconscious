//
//  FirstRunCreateSphereView.swift
//  Subconscious (iOS)
//
//  Created by Gordon Brander on 1/20/23.
//
import ObservableStore
import SwiftUI

struct FirstRunSphereView: View {
    @ObservedObject var app: Store<AppModel>
    @Environment(\.colorScheme) var colorScheme
    
    var did: Did? {
        Did(app.state.sphereIdentity ?? "")
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                VStack(spacing: AppTheme.padding) {
                    if let name = app.state.nicknameFormField.validated  {
                        HStack(spacing: 0) {
                            Text("Hi, ")
                                .foregroundColor(.secondary)
                            PetnameView(petname: name)
                            Text(".")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let did = did {
                        StackedGlowingImage() {
                            GenerativeProfilePic(
                                did: did,
                                size: 80
                            )
                        }
                        .padding(AppTheme.padding)
                    }
                    
                    Text("This is your sphere. It stores your data.")
                        .foregroundColor(.secondary)
                    
                    Text("Your sphere connects to Noosphere allowing you to explore and follow other spheres.")
                        .foregroundColor(.secondary)
                }
                .multilineTextAlignment(.center)
                
                Spacer()
                
                NavigationLink(
                    destination: {
                        FirstRunRecoveryView(app: app)
                    },
                    label: {
                        Text("Got it")
                    }
                )
                .buttonStyle(PillButtonStyle())
            }
            .padding()
            .background(
                AppTheme.onboarding
                    .appBackgroundGradient(colorScheme)
            )
        }
        .navigationTitle("Your Sphere")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FirstRunSphereView_Previews: PreviewProvider {
    static var previews: some View {
        FirstRunSphereView(
            app: Store(
                state: AppModel(),
                environment: AppEnvironment()
            )
        )
    }
}