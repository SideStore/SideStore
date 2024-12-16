//
//  AnisetteServerList.swift
//  SideStore
//
//  Created by ny on 6/18/24.
//  Copyright © 2024 SideStore. All rights reserved.
//

import UIKit
import SwiftUI
import AltStoreCore

typealias SUIButton = SwiftUI.Button

// MARK: - AnisetteServerData
struct AnisetteServerData: Codable {
    let servers: [Server]
}

// MARK: - Server
struct Server: Codable {
    var name: String
    var address: String
}

class AnisetteViewModel: ObservableObject {
    @Published var selected: String = ""

    @Published var source: String = "https://servers.sidestore.io/servers.json"
    @Published var servers: [Server] = []
    
    init() {
        // using the custom Anisette list
        if !UserDefaults.standard.menuAnisetteList.isEmpty {
            self.source = UserDefaults.standard.menuAnisetteList
        }
    }
    
    @MainActor
    func getCurrentListOfServers(_ completionHandler: @escaping (Result<Void, Error>) -> Void = {_ in }) {
        // dispatch fetch operation but don't do a blocking wait for results
        Task {
            do {
                let anisetteServers = try await AnisetteViewModel.getListOfServers(serverSource: self.source)
                // Update UI-related state on the main thread
                self.servers = anisetteServers
                print("AnisetteViewModel: Server list refresh request completed for sourceURL: \(self.source)")
                completionHandler(.success(()))
            } catch {
                print("AnisetteViewModel: Server list refresh request Failed for sourceURL: \(self.source) Error: \(error)")
                completionHandler(.failure(error))
            }
        }
    }
    
    static func getListOfServers(serverSource: String) async throws -> [Server] {
        var aniServers: [Server] = []

        guard let url = URL(string: serverSource) else {
            return aniServers
        }

        // DO NOT use local cache when fetching anisette servers
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            // Use async/await pattern here, avoiding CheckedContinuation directly
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check if the response is valid and has a 2xx HTTP status code
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                // Handle non-2xx status codes
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw NSError(domain: "AnisetteViewModel: ServerError", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Request failed with status code: \(statusCode)"])
            }
            
            let decoder = Foundation.JSONDecoder()
            let servers = try decoder.decode(AnisetteServerData.self, from: data)
            print("AnisetteViewModel: JSON Decode successful for sourceURL: \(serverSource) servers: \(servers)")
            aniServers.append(contentsOf: servers.servers)
            // Store server addresses as list
            UserDefaults.standard.menuAnisetteServersList = aniServers.map(\.address)
            return aniServers
        } catch {
            if let urlError = error as? URLError {
                print("AnisetteViewModel: URL Error: \(urlError.localizedDescription)")
            } else if let decodingError = error as? DecodingError {
                print("AnisetteViewModel: Failed to decode JSON: \(decodingError.localizedDescription)")
            } else {
                print("AnisetteViewModel: An unexpected error occurred: \(error.localizedDescription)")
            }
            throw error // Propagate the error
        }
    }
}

struct AnisetteServersView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject var viewModel: AnisetteViewModel = AnisetteViewModel()
    @State var selected: String? = nil
    @State private var showingConfirmation = false
    var errorCallback: () -> ()
    var refreshCallback: (Result<Void, any Error>) -> Void

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
                .onAppear {
                    viewModel.getCurrentListOfServers(refreshCallback)
                }
            VStack {
                if #available(iOS 16.0, *) {
                    SwiftUI.List($viewModel.servers, id: \.address, selection: $selected) { server in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(server.name.wrappedValue)")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("\(server.address.wrappedValue)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if selected != nil {
                                if server.address.wrappedValue == selected {
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                        .onAppear {
                                            UserDefaults.standard.menuAnisetteURL = server.address.wrappedValue
                                            print(UserDefaults.synchronize(.standard)())
                                            print(UserDefaults.standard.menuAnisetteURL)
                                            print(server.address.wrappedValue)
                                        }
                                }
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.secondarySystemBackground)))
                        .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 5)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .listRowBackground(Color(UIColor.systemBackground))
                } else {
                    List(selection: $selected) {
                        ForEach($viewModel.servers, id: \.name) { server in
                            VStack {
                                HStack {
                                    Text("\(server.name.wrappedValue)")
                                        .foregroundColor(.primary)
                                        .frame(alignment: .center)
                                    Text("\(server.address.wrappedValue)")
                                        .foregroundColor(.secondary)
                                        .frame(alignment: .center)
                                }
                            }
                            Spacer()
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.secondarySystemBackground)))
                        .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 5)
                    }
                    .listStyle(.plain)
                }
                
                VStack(spacing: 16) {
                    TextField("Anisette Server List", text: $viewModel.source)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.secondarySystemFill)))
                        .foregroundColor(.primary)
                        .frame(height: 60)
                        .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 5)
                        .onChange(of: viewModel.source) { newValue in
                            UserDefaults.standard.menuAnisetteList = newValue
//                            viewModel.getCurrentListOfServers(refreshCallback)        // don't spam
                            viewModel.getCurrentListOfServers()
                        }

                    HStack(spacing: 16) {
                        SUIButton(action: {
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            HStack{
                                Spacer()
                                Text("Back")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor))
                        .foregroundColor(.white)
                        .shadow(color: Color.accentColor.opacity(0.4), radius: 10, x: 0, y: 5)

                        SUIButton(action: {
                            viewModel.getCurrentListOfServers(refreshCallback)
                        }) {
                            HStack{
                                Text("Refresh Servers")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor))
                        .foregroundColor(.white)
                        .shadow(color: Color.accentColor.opacity(0.4), radius: 10, x: 0, y: 5)
                        
                    }

                    SUIButton(action: {
                        showingConfirmation = true
                    }) {
                        Text("Reset adi.pb")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.red))
                    .foregroundColor(.white)
                    .shadow(color: Color.red.opacity(0.4), radius: 10, x: 0, y: 5)
                    .alert(isPresented: $showingConfirmation) {
                        Alert(
                            title: Text("Reset adi.pb"),
                            message: Text("are you sure to clear the adi.pb from keychain？"),
                            primaryButton: .default(Text("do it")) {
                                #if !DEBUG
                                if Keychain.shared.adiPb != nil {
                                    Keychain.shared.adiPb = nil
                                }
                                #endif
                                print("Cleared adi.pb from keychain")
                                errorCallback()
                                presentationMode.wrappedValue.dismiss()
                            },
                            secondaryButton: .cancel(Text("cancel")) {
                                print("canceled")
                            }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .navigationBarHidden(true)
        .navigationTitle("")
    }
}
