import Darwin
import Foundation

if ProcessInfo.processInfo.environment["GOJO_HELPER_HANDSHAKE_STDOUT_V1"] == "1" {
    let arguments = CommandLine.arguments
    guard let flag = arguments.firstIndex(of: "--gojo-helper-handshake"),
          arguments.indices.contains(flag + 1),
          let probeID = UUID(uuidString: arguments[flag + 1]) else {
        FileHandle.standardOutput.write(Data("{\"available\":false,\"error\":\"A probe identifier is required\"}\n".utf8))
        exit(2)
    }
    Task { @MainActor in
        var result: [String: Any] = ["probeID": probeID.uuidString]
        let status: Int32
        do {
            let helper = try await XPCHelperClient.shared.helperPermissionStatus()
            result["available"] = true
            result["helperInstanceID"] = helper.instanceID.uuidString
            result["protocolVersion"] = helper.protocolVersion
            result["accessibilityAuthorized"] = helper.accessibilityAuthorized
            status = 0
        } catch {
            result["available"] = false
            result["error"] = error.localizedDescription
            status = 1
        }
        do {
            var data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            data.append(0x0A)
            FileHandle.standardOutput.write(data)
            exit(status)
        } catch {
            exit(2)
        }
    }
    dispatchMain()
} else {
    DynamicNotchApp.main()
}
