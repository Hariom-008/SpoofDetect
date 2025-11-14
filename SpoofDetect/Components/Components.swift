import Foundation

class Component {
    static var libraryFound: Bool = false
    
    init() {
        // In iOS, native libraries are linked at compile time
        // or loaded dynamically using dlopen if needed
        Component.libraryFound = true
    }
    
    func createInstance() -> UnsafeMutableRawPointer? {
        fatalError("createInstance() must be implemented by subclass")
    }
    
    func destroy() {
        fatalError("destroy() must be implemented by subclass")
    }
    
    // Helper method to get the class-specific tag
    var tag: String {
        return String(describing: type(of: self))
    }
}
