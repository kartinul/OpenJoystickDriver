import Foundation
import Testing

@testable import OpenJoystickDriverKit

// Transcripts captured from the current drivers; later slices must not change these values.
extension DriverLifecycleCharacterizationTests {
  @Test
  func gameSirEnhancedHID8KTranscript() throws {
    #expect(
      try transcript(Self.gameSirEnhancedHID8K) == [
        "capabilities rumble=[leftMain,rightMain] binary=[]",
        "capabilities lighting=[programmableBrightness,programmableColor]",
        "capabilities triggers=[]", "usb.startup interval=0 retries=[] packets=0",
        "usb.keepAlive nil", "usb.deferred inputs=2 packets=0", "usb.deferred drained=0",
        "usb.connection[connected] packets=0", "usb.connection[disconnected] packets=0",
        "hid.startupOutput[USB] interval=20000000 required=false beforeReads=false reports=1",
        "  id=0x0f n=64", "    0ff2000000000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "hid.featureReads[USB] validates=false requests=[]",
        "hid.featureReplies[USB] accepts=false", "hid.featureReports[USB] reports=0",
        "hid.startupOutput[Bluetooth] interval=20000000 required=false beforeReads=false reports=1",
        "  id=0x0f n=64", "    0ff2000000000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "hid.featureReads[Bluetooth] validates=false requests=[]",
        "hid.featureReplies[Bluetooth] accepts=false", "hid.featureReports[Bluetooth] reports=0",
        "hid.startupOutput[BLE] interval=20000000 required=false beforeReads=false reports=1",
        "  id=0x0f n=64", "    0ff2000000000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "hid.featureReads[BLE] validates=false requests=[]",
        "hid.featureReplies[BLE] accepts=false", "hid.featureReports[BLE] reports=0",
        "hid.startupOutput[nil] interval=20000000 required=false beforeReads=false reports=1",
        "  id=0x0f n=64", "    0ff2000000000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "hid.featureReads[nil] validates=false requests=[]",
        "hid.featureReplies[nil] accepts=false", "hid.featureReports[nil] reports=0",
        "hid.featureReports[presence] reports=0", "hid.shutdownFeatureReports reports=0",
        "hid.periodic interval=500000000 reports=1", "  id=0x0f n=64",
        "    0ff2000000000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "hid.statusRequest nil", "hid.recovery[USB] supported=false beforeStartup=0 afterStartup=0",
        "hid.recovery afterExpiry=0", "presence requiresConnection=false",
        "presence input#0 change=nil", "presence input#1 change=nil", "liveness timeout=nil",
        "liveness observation=nil", "liveness format=nil", "battery=84% charging wired-power=yes",
        "out[cold].hidRumble motors=[leftMain,rightMain] binary=[] minInterval=20000000",
        "  id=0x0f n=64", "    0f20665540800000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "out[cold].color default=0,128,255", "out[cold].color plan=nil",
        "out[cold].hidBrightnessPlan", "  plan=nil", "out[cold].usbBrightness packets=nil",
        "out[ready].hidRumble motors=[leftMain,rightMain] binary=[] minInterval=20000000",
        "  id=0x0f n=64", "    0f20665540800000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "out[ready].color default=0,128,255", "  plan interval=20000000 reports=4",
        "  id=0x0f n=64", "    0f0320000c0300d2430000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x0f n=64",
        "    0f032000100300d2430000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x0f n=64",
        "    0f032000140300d2430000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x0f n=64",
        "    0f032000180300d2430000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "out[ready].hidBrightnessPlan", "  plan interval=0 reports=1", "  id=0x0f n=64",
        "    0f03200001013200000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "out[ready].usbBrightness packets=nil",
        "out[reset].hidRumble motors=[leftMain,rightMain] binary=[] minInterval=20000000",
        "  id=0x0f n=64", "    0f20665540800000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "out[reset].color default=0,128,255", "out[reset].color plan=nil",
        "out[reset].hidBrightnessPlan", "  plan=nil", "out[reset].usbBrightness packets=nil",
      ]
    )
  }

  @Test
  func hidDescriptorTranscript() throws {
    #expect(
      try transcript(Self.hidDescriptor) == [
        "capabilities rumble=[] binary=[]", "capabilities lighting=[]", "capabilities triggers=[]",
        "usb.startup interval=0 retries=[] packets=0", "usb.keepAlive nil",
        "usb.deferred inputs=0 packets=0", "usb.deferred drained=0",
        "usb.connection[connected] packets=0", "usb.connection[disconnected] packets=0",
        "hid.startupOutput[USB] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[USB] validates=false requests=[]",
        "hid.featureReplies[USB] accepts=false", "hid.featureReports[USB] reports=0",
        "hid.startupOutput[Bluetooth] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[Bluetooth] validates=false requests=[]",
        "hid.featureReplies[Bluetooth] accepts=false", "hid.featureReports[Bluetooth] reports=0",
        "hid.startupOutput[BLE] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[BLE] validates=false requests=[]",
        "hid.featureReplies[BLE] accepts=false", "hid.featureReports[BLE] reports=0",
        "hid.startupOutput[nil] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[nil] validates=false requests=[]",
        "hid.featureReplies[nil] accepts=false", "hid.featureReports[nil] reports=0",
        "hid.featureReports[presence] reports=0", "hid.shutdownFeatureReports reports=0",
        "hid.periodic nil", "hid.statusRequest nil",
        "hid.recovery[USB] supported=false beforeStartup=0 afterStartup=0",
        "hid.recovery afterExpiry=0", "presence requiresConnection=false", "liveness timeout=nil",
        "liveness observation=nil", "liveness format=nil", "battery=nil",
      ]
    )
  }
}
