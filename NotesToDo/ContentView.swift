//
//  ContentView.swift
//  NotesToDo
//
//  Created by Volodymyr Boichentsov on 20/10/2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        NotesListView()
            .frame(minWidth: 800, minHeight: 600)
    }
}

#Preview {
    ContentView()
}
