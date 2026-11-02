import Foundation
import Testing
@testable import MacPulseDomain

@Suite("FileCategorizer")
struct FileCategorizerTests {
    @Test func extensionsMapToCategories() {
        #expect(FileCategorizer.category(forPath: "/Users/t/Movies/trip.MOV") == .video)
        #expect(FileCategorizer.category(forPath: "/Users/t/x/report.pdf") == .documents)
        #expect(FileCategorizer.category(forPath: "/Users/t/x/backup.dmg") == .archives)
        #expect(FileCategorizer.category(forPath: "/Users/t/x/README") == .other)
        #expect(FileCategorizer.category(forPath: "/Applications/Xcode.app", isPackage: true) == .applications)
    }

    @Test func locationBeatsExtension() {
        #expect(FileCategorizer.category(forPath: "/Users/t/Library/Caches/com.app/thumb.png") == .caches)
        #expect(FileCategorizer.category(forPath: "/Users/t/.Trash/old.mov") == .trash)
        #expect(FileCategorizer.category(forPath: "/Users/t/Library/Logs/app/run.txt") == .logs)
        #expect(FileCategorizer.category(forPath: "/Users/t/Library/Developer/Xcode/DerivedData/App/Build/x.o") == .caches)
        #expect(FileCategorizer.category(forPath: "/private/var/folders/ab/cd/T/upload.bin") == .temporary)
    }
}
