// swift-tools-version: 5.9
import PackageDescription
let package=Package(name:"RadarCore",platforms:[.iOS(.v17)],
 products:[.library(name:"RadarCore",targets:["RadarCore"])],
 targets:[.target(name:"RadarCore",path:"Sources/RadarCore"),
          .testTarget(name:"RadarCoreTests",dependencies:["RadarCore"],path:"Tests/RadarCoreTests")])
