import AppKit
import Foundation

let size=1024
let pixel=NSSize(width:size,height:size)
let image=NSImage(size:pixel)
image.lockFocus()
let rect=NSRect(origin:.zero,size:pixel)
NSColor(calibratedRed:0.043,green:0.067,blue:0.082,alpha:1).setFill()
rect.fill()
let signal=NSColor(calibratedRed:0.73,green:0.95,blue:0.45,alpha:1)
signal.setStroke()
let ring=NSBezierPath(ovalIn:NSRect(x:208,y:208,width:608,height:608))
ring.lineWidth=55
ring.stroke()
let arc=NSBezierPath()
arc.lineWidth=70
arc.lineCapStyle = .round
arc.move(to:NSPoint(x:360,y:320))
arc.line(to:NSPoint(x:360,y:705))
arc.curve(to:NSPoint(x:662,y:618),
          controlPoint1:NSPoint(x:620,y:742),
          controlPoint2:NSPoint(x:702,y:735))
arc.curve(to:NSPoint(x:462,y:476),
          controlPoint1:NSPoint(x:665,y:500),
          controlPoint2:NSPoint(x:550,y:494))
arc.stroke()
let dot=NSBezierPath(ovalIn:NSRect(x:659,y:315,width:75,height:75))
signal.setFill();dot.fill()
image.unlockFocus()
let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
let asset=root.appendingPathComponent("RadarApp/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at:asset,withIntermediateDirectories:true)
guard let tiff=image.tiffRepresentation,
      let bitmap=NSBitmapImageRep(data:tiff),
      let png=bitmap.representation(using:.png,properties:[:]) else {
    fatalError("Unable to render Radar app icon")
}
try png.write(to:asset.appendingPathComponent("AppIcon.png"))
print("Generated native Radar app icon")
