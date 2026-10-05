//
//  ContentView.swift
//  Orbit Breaker Watch App
//
//  Created by Edson Barlow on 10/5/26.
//

import OrbitEngine
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("\((try? LevelLoader.loadAll().count) ?? 0) levels")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
