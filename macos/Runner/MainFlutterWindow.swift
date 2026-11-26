import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // On macOS Flutter starts its engine when the view first appears. This
    // window stays hidden until the panel is asked for, so without this the
    // app would sit in the menu bar doing nothing: no clipboard watching and
    // no hot edge.
    flutterViewController.engine.run(withEntrypoint: nil)

    super.awakeFromNib()
  }
}
