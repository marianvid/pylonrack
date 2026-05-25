import AppKit

final class RackFolderDelegate: NSObject, NSOpenSavePanelDelegate {

    // Called when user clicks Open — blocks confirmation if folder is invalid
    func panel(_ sender: Any, validate url: URL) throws {
        guard LocalSlotConfig.load(from: url) != nil else {
            throw NSError(
                domain: "PylonRack",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "This folder is not a valid PylonRack application.",
                    NSLocalizedRecoverySuggestionErrorKey:
                        "The selected folder must contain a rack.json file with name, start, host and port fields."
                ]
            )
        }
    }
}
