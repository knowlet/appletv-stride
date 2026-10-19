import Foundation

enum PlistError: Error { case invalid(String) }
for target in ["iPhone", "TV"] {
    let path = "Apps/\(target)/Info.plist"
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          values["NSBonjourServices"] as? [String] == ["_stride._tcp"],
          let purpose = values["NSLocalNetworkUsageDescription"] as? String, !purpose.isEmpty,
          values["NSAppTransportSecurity"] == nil else { throw PlistError.invalid(path) }
    if target == "iPhone" {
        guard values["NSMotionUsageDescription"] is String,
              values["NSCameraUsageDescription"] is String else { throw PlistError.invalid(path) }
    }
}
print("Property lists validated; no global ATS bypass.")
