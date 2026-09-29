import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverUSB

struct DiagnoseCommand { let serviceCallTimeoutSeconds: Double }

struct DiagnoseUSBScanFailure: Error, Sendable { let message: String }
