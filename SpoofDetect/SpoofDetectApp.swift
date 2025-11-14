// SpoofDetectApp.swift
import SwiftUI

@main
struct SpoofDetectApp: App {
    var body: some Scene {
        WindowGroup {
            VStack{
                ContentView()
            }
            .onAppear{
               debugBundleResources()
            }
        }
    }
    
}

func debugBundleResources() {
    let fm = FileManager.default
    if let resPath = Bundle.main.resourcePath {
        print("🔍 resourcePath:", resPath)
        let top = (try? fm.contentsOfDirectory(atPath: resPath)) ?? []
        print("🔍 top-level bundle contents:", top)

        if top.contains("detection") {
            let detPath = resPath + "/detection"
            let detFiles = (try? fm.contentsOfDirectory(atPath: detPath)) ?? []
            print("🔍 detection folder contents:", detFiles)
        } else {
            print("❌ detection folder not in bundle")
        }
    }
}
