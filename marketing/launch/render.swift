import AppKit
import CoreText
import Foundation

// Landscape film, revision 3. Captured product states with explicit workflow connections.
// Positions are baselines or measured ink bounds, never estimated font-size offsets.
let args = CommandLine.arguments
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("marketing/launch/renders")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let width = 1920, height = 1080, fps = 60
let duration = 27.0
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
let paper = "F2F1ED", ink = "252723", quiet = "777B73", accent = "AA5C3E"
var c: CGContext!

func color(_ s: String, _ a: Double = 1) -> CGColor {
    let n = UInt32(s, radix:16)!
    return CGColor(colorSpace:rgb, components:[Double((n>>16)&255)/255, Double((n>>8)&255)/255, Double(n&255)/255, a])!
}
func clamp(_ v: Double) -> Double { min(1,max(0,v)) }
func ease(_ v: Double) -> Double { let x=clamp(v); return x*x*x*(x*(x*6-15)+10) }
func progress(_ t: Double,_ a: Double,_ b: Double) -> Double { ease((t-a)/(b-a)) }
func mix(_ a: Double,_ b: Double,_ p: Double) -> Double { a+(b-a)*p }
func save(_ f: () -> Void) { c.saveGState();f();c.restoreGState() }
func layer(_ opacity: Double,_ f: () -> Void) {
    guard opacity>0.00001 else { return }
    save { c.setAlpha(clamp(opacity));c.beginTransparencyLayer(auxiliaryInfo:nil);f();c.endTransparencyLayer() }
}
func transform(_ x: Double,_ y: Double,_ s: Double=1,_ f: () -> Void) {
    save { c.translateBy(x:x,y:y);c.scaleBy(x:s,y:s);f() }
}
func rect(_ x: Double,_ y: Double,_ w: Double,_ h: Double,_ col: String) {
    c.setFillColor(color(col));c.fill(CGRect(x:x,y:y,width:w,height:h))
}
func line(_ x: Double,_ y: Double,_ xx: Double,_ yy: Double,_ col: String,_ w: Double=1) {
    c.setStrokeColor(color(col));c.setLineWidth(w);c.move(to:CGPoint(x:x,y:y));c.addLine(to:CGPoint(x:xx,y:yy));c.strokePath()
}
func dot(_ p: CGPoint,_ r: Double,_ col: String) {
    c.setFillColor(color(col));c.fillEllipse(in:CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2))
}
var fonts:[String:CTFont]=[:]
func font(_ size:Double,_ face:String="sans") -> CTFont {
    if face == "ink" { return CTFontCreateWithGraphicsFont(exportedFont,size,nil,nil) }
    let key="\(face):\(size)"; if let f=fonts[key] { return f }
    let name: String
    switch face {
    case "specimen":name="Futura-Medium"
    case "serif":name="Baskerville"
    case "italic":name="Baskerville-Italic"
    case "medium":name="HelveticaNeue-Medium"
    default:name="HelveticaNeue"
    }
    let f=CTFontCreateWithName(name as CFString,size,nil);fonts[key]=f;return f
}
func typeset(_ s:String,_ size:Double,_ face:String="sans",_ col:String=ink) -> CTLine {
    // Omit .kern so Core Text preserves the font's native pair kerning.
    CTLineCreateWithAttributedString(NSAttributedString(string:s,attributes:[.font:font(size,face),.foregroundColor:color(col)]))
}
func inkBounds(_ s:String,_ size:Double,_ face:String="sans") -> CGRect {
    CTLineGetBoundsWithOptions(typeset(s,size,face),[.useGlyphPathBounds])
}
func text(_ s:String,_ x:Double,_ baseline:Double,_ size:Double,_ col:String=ink,_ face:String="sans",_ align:String="left") {
    let l=typeset(s,size,face,col), b=CTLineGetBoundsWithOptions(l,[.useGlyphPathBounds])
    let shift = align=="center" ? -b.midX : (align=="right" ? -b.maxX : -b.minX)
    save { c.textMatrix=CGAffineTransform(scaleX:1,y:-1);c.textPosition=CGPoint(x:x+shift,y:baseline);CTLineDraw(l,c) }
}
func sheet(_ x:Double,_ y:Double,_ w:Double,_ h:Double,_ col:String) {
    save { c.setShadow(offset:CGSize(width:0,height:12),blur:38,color:color("22241F",0.075));rect(x,y,w,h,col) }
}
func image(_ img:CGImage,_ r:CGRect) {
    save { c.translateBy(x:r.minX,y:r.maxY);c.scaleBy(x:1,y:-1);c.draw(img,in:CGRect(x:0,y:0,width:r.width,height:r.height)) }
}
let icon=NSImage(contentsOf:root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"))!.cgImage(forProposedRect:nil,context:nil,hints:nil)!

// Product captures come from a separate, disposable QA application container.
// These crops omit unrelated QA project names and keep the actual product controls.
let assetRoot=root.appendingPathComponent("marketing/launch/assets/v3")
let rawRoot=output.appendingPathComponent("v3-captures")
struct Capture {let name:String;let source:String;let crop:CGRect}
let captures:[Capture] = [
    Capture(name:"library",source:"library.png",crop:CGRect(x:0,y:78,width:2480,height:1000)),
    Capture(name:"create",source:"create-typeboard.png",crop:CGRect(x:510,y:80,width:1970,height:990)),
    Capture(name:"spaces",source:"spaces.png",crop:CGRect(x:512,y:180,width:1968,height:880)),
    Capture(name:"import",source:"import.png",crop:CGRect(x:25,y:300,width:2030,height:725)),
    Capture(name:"editor",source:"editor.png",crop:CGRect(x:574,y:462,width:1890,height:950)),
    Capture(name:"return",source:"ink-library.png",crop:CGRect(x:0,y:80,width:1220,height:880)),
    Capture(name:"poster",source:"ink-spaces.png",crop:CGRect(x:512,y:180,width:1968,height:880))
]
if args.contains("--prepare-assets") {
    try FileManager.default.createDirectory(at:assetRoot,withIntermediateDirectories:true)
    for shot in captures {
        let original=NSImage(contentsOf:rawRoot.appendingPathComponent(shot.source))!.cgImage(forProposedRect:nil,context:nil,hints:nil)!
        let crop=original.cropping(to:shot.crop)!
        try NSBitmapImageRep(cgImage:crop).representation(using:.png,properties:[:])!.write(to:assetRoot.appendingPathComponent(shot.name+".png"))
    }
    print("Prepared seven product crops from the isolated QA workflow.")
    exit(0)
}
let exportedFont=CGFont(CGDataProvider(url:assetRoot.appendingPathComponent("Ink.ttf") as CFURL)!)!
var shots:[String:CGImage]=[:]
for shot in captures {
    guard let im=NSImage(contentsOf:assetRoot.appendingPathComponent(shot.name+".png"))?.cgImage(forProposedRect:nil,context:nil,hints:nil) else {fatalError("Missing capture: \(shot.name). Run --prepare-assets with the local QA capture bundle.")}
    shots[shot.name]=im
}

// One grid, native Core Text kerning and optical alignment throughout.
// Headings enter at full opacity through a 240 ms vertical mask.
func heading(_ title:String,_ stage:String,_ local:Double,_ detail:String="") {
    text(stage,128,100,26,quiet)
    let p=progress(local,0,0.24)
    save {
        c.clip(to:CGRect(x:126,y:127,width:1670,height:108))
        text(title,128,213+105*(1-p),76)
    }
    if !detail.isEmpty { text(detail,130,268,27,quiet) }
}
let navNames=["Library","Spaces","Letterform Editor"]
let navX=[128.0,670.0,1212.0]
func navigation(_ current:Int,_ previous:Int,_ local:Double) {
    line(128,980,1792,980,"D3D5CE")
    for i in 0..<3 {text(navNames[i],navX[i],1034,25,i==current ? ink:quiet)}
    let p=progress(local,0,0.32), x=mix(navX[previous],navX[current],p)
    let w=mix(inkBounds(navNames[previous],25).width,inkBounds(navNames[current],25).width,p)
    rect(x,978,w,3,ink)
}
func product(_ key:String,_ box:CGRect,_ local:Double,_ enter:Bool=true,_ anchor:Double=0.5) {
    let im=shots[key]!, ratio=Double(im.width)/Double(im.height)
    let fit=min(box.width/Double(im.width),box.height/Double(im.height))
    let w=Double(im.width)*fit,h=w/ratio
    let p=enter ? progress(local,0,0.38):1
    let zoom=mix(1.018,1,progress(local,0,0.8))
    let x=box.minX+(box.width-w)/2, y=box.minY+(box.height-h)*anchor
    save {
        c.setShadow(offset:CGSize(width:0,height:6),blur:18,color:color("171C20",0.09))
        rect(x+60*(1-p),y,w,h,"1A1C21")
    }
    save {
        c.clip(to:CGRect(x:x+60*(1-p),y:y,width:w,height:h))
        image(im,CGRect(x:x+60*(1-p)-(w*zoom-w)/2,y:y-(h*zoom-h)/2,width:w*zoom,height:h*zoom))
    }
}
// The exact five paths in the original handwriting fixture, not a stock typeface.
func handwritingPaths()->[CGPath] {
    var a:[CGPath]=[]
    let n=CGMutablePath();n.move(to:CGPoint(x:30,y:173));n.addQuadCurve(to:CGPoint(x:45,y:91),control:CGPoint(x:35,y:130));a.append(n)
    let nn=CGMutablePath();nn.move(to:CGPoint(x:39,y:128));nn.addCurve(to:CGPoint(x:92,y:128),control1:CGPoint(x:67,y:67),control2:CGPoint(x:105,y:80));nn.addLine(to:CGPoint(x:82,y:174));a.append(nn)
    let o=CGMutablePath();o.move(to:CGPoint(x:196,y:89));o.addCurve(to:CGPoint(x:168,y:177),control1:CGPoint(x:142,y:64),control2:CGPoint(x:132,y:171));o.addCurve(to:CGPoint(x:196,y:89),control1:CGPoint(x:211,y:188),control2:CGPoint(x:234,y:83));a.append(o)
    let p=CGMutablePath();p.move(to:CGPoint(x:270,y:218));p.addLine(to:CGPoint(x:302,y:91));a.append(p)
    let pp=CGMutablePath();pp.move(to:CGPoint(x:294,y:124));pp.addCurve(to:CGPoint(x:342,y:150),control1:CGPoint(x:331,y:66),control2:CGPoint(x:363,y:99));pp.addQuadCurve(to:CGPoint(x:286,y:168),control:CGPoint(x:324,y:186));a.append(pp)
    let i=CGMutablePath();i.move(to:CGPoint(x:413,y:172));i.addLine(to:CGPoint(x:438,y:91));a.append(i)
    let j=CGMutablePath();j.move(to:CGPoint(x:557,y:88));j.addLine(to:CGPoint(x:531,y:180));j.addQuadCurve(to:CGPoint(x:499,y:207),control:CGPoint(x:524,y:215));a.append(j)
    return a
}
func flatten(_ path:CGPath)->[CGPoint] {
    var points:[CGPoint]=[], last=CGPoint.zero
    path.applyWithBlock { raw in
        let e=raw.pointee, q=e.points, origin=last
        switch e.type {
        case .moveToPoint:points.append(q[0]);last=q[0]
        case .addLineToPoint:points.append(q[0]);last=q[0]
        case .addQuadCurveToPoint:
            for i in 1...80 {let t=Double(i)/80,u=1-t;points.append(CGPoint(x:u*u*origin.x+2*u*t*q[0].x+t*t*q[1].x,y:u*u*origin.y+2*u*t*q[0].y+t*t*q[1].y))};last=q[1]
        case .addCurveToPoint:
            for i in 1...80 {let t=Double(i)/80,u=1-t;points.append(CGPoint(x:u*u*u*origin.x+3*u*u*t*q[0].x+3*u*t*t*q[1].x+t*t*t*q[2].x,y:u*u*u*origin.y+3*u*u*t*q[0].y+3*u*t*t*q[1].y+t*t*t*q[2].y))};last=q[2]
        default:break
        }
    }
    return points
}
let handwriting=handwritingPaths().map(flatten)
func drawStroke(_ points:[CGPoint],_ fraction:Double) {
    let lengths=zip(points,points.dropFirst()).map {hypot($1.x-$0.x,$1.y-$0.y)}
    var remaining=lengths.reduce(0,+)*clamp(fraction)
    guard remaining>0 else{return}
    c.beginPath();c.move(to:points[0])
    for i in 0..<lengths.count {
        let l=lengths[i]
        if remaining>=l {c.addLine(to:points[i+1]);remaining-=l}
        else {let r=remaining/l;c.addLine(to:CGPoint(x:mix(points[i].x,points[i+1].x,r),y:mix(points[i].y,points[i+1].y,r)));break}
    }
    c.strokePath()
}
func drawing(_ local:Double) {
    transform(252,320,2.55) {
        c.setStrokeColor(color(ink));c.setLineWidth(13);c.setLineCap(.round);c.setLineJoin(.round)
        for (i,path) in handwriting.enumerated() {drawStroke(path,clamp((local-Double(i)*0.16)/0.28))}
        if local>1.14 {dot(CGPoint(x:455,y:54),8,ink)}
        if local>1.28 {dot(CGPoint(x:565,y:51),8,ink)}
    }
    text("Your drawings become editable glyphs.",128,925,30,quiet)
}
func exportFont(_ local:Double) {
    let p=progress(local,0,0.38)
    text("pin",310-60*(1-p),720,550,ink,"ink")
    let x=1320.0,y=350+36*(1-p),w=330.0,h=470.0,fold=65.0
    save {
        let outline=CGMutablePath()
        outline.move(to:CGPoint(x:x,y:y));outline.addLine(to:CGPoint(x:x+w-fold,y:y))
        outline.addLine(to:CGPoint(x:x+w,y:y+fold));outline.addLine(to:CGPoint(x:x+w,y:y+h))
        outline.addLine(to:CGPoint(x:x,y:y+h));outline.closeSubpath()
        c.setFillColor(color("FAF9F5"));c.setStrokeColor(color("B2B6AD"));c.setLineWidth(2)
        c.addPath(outline);c.drawPath(using:.fillStroke)
        line(x+w-fold,y,x+w-fold,y+fold,"B2B6AD",2);line(x+w-fold,y+fold,x+w,y+fold,"B2B6AD",2)
        text("TrueType",x+38,y+107,27,quiet)
        text("Ink.ttf",x+38,y+h-53,54)
    }
    let arrow=progress(local,0.2,0.55)
    line(1050,594,1050+175*arrow,594,"A0A69B",2)
    if arrow>0.99 {line(1213,584,1225,594,"A0A69B",2);line(1213,604,1225,594,"A0A69B",2)}
}
func closing(_ local:Double) {
    let p=progress(local,0,0.32)
    let s=mix(0.84,1,p)
    transform(960,363,s) {image(icon,CGRect(x:-112,y:-112,width:224,height:224))}
    text("Typefield",960,640,116,ink,"medium","center")
    text("Your entire type workflow.",960,730,36,quiet,"sans","center")
    text("For Mac",960,922,25,quiet,"sans","center")
}
struct Scene {let start:Double;let title:String;let stage:String;let active:Int;let key:String;let detail:String}
let scenes=[
    Scene(start:0,title:"Find your next font.",stage:"Library",active:0,key:"library",detail:""),
    Scene(start:2.6,title:"Take it into Spaces.",stage:"Library → Spaces",active:1,key:"create",detail:"Select fonts. Create a typeboard."),
    Scene(start:4.7,title:"Build a layout with it.",stage:"Spaces",active:1,key:"spaces",detail:""),
    Scene(start:8,title:"Or make a font of your own.",stage:"Letterform Editor",active:2,key:"drawing",detail:""),
    Scene(start:10,title:"Import your letter artwork.",stage:"Letterform Editor",active:2,key:"import",detail:""),
    Scene(start:12.7,title:"Refine every curve.",stage:"Letterform Editor",active:2,key:"editor",detail:"Bézier editing, metrics and spacing."),
    Scene(start:16.1,title:"Export a real font.",stage:"Letterform Editor → Library",active:2,key:"export",detail:"Save your outlines as a TrueType font."),
    Scene(start:18.5,title:"Add it to your Library.",stage:"Library",active:0,key:"return",detail:"Add the folder containing your exported font."),
    Scene(start:21.2,title:"Use your font in Spaces.",stage:"Library → Spaces",active:1,key:"poster",detail:"")
]
func frame(_ t:Double)->CGContext {
    let ctx=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:rgb,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    c=ctx;c.translateBy(x:0,y:Double(height));c.scaleBy(x:1,y:-1)
    c.setAllowsAntialiasing(true);c.setShouldAntialias(true);c.interpolationQuality = .high
    rect(0,0,1920,1080,paper)
    if t>=24.5 {closing(t-24.5);return ctx}
    let index=scenes.lastIndex(where:{$0.start<=t})!, scene=scenes[index],local=t-scene.start
    heading(scene.title,scene.stage,index == 0 ? local+0.24:local,scene.detail)
    navigation(scene.active,index>0 ? scenes[index-1].active:0,local)
    if scene.key=="drawing" {drawing(local);return ctx}
    if scene.key=="export" {exportFont(local);return ctx}
    if scene.key=="return" {
        product("return",CGRect(x:128,y:305,width:890,height:640),local)
        text("Your font.",1150,528,51)
        text("Ready to use.",1150,596,51)
    } else {
        let top=scene.detail.isEmpty ? 268.0:305.0
        product(scene.key,CGRect(x:128,y:top,width:1664,height:945-top),local,true)
    }
    return ctx
}
func png(_ ctx:CGContext,_ url:URL) throws {
    try NSBitmapImageRep(cgImage:ctx.makeImage()!).representation(using:.png,properties:[:])!.write(to:url)
}
if args.contains("--stills") {
    for t in [0.0,0.12,0.4,1.4,2.8,3.6,4.9,6.4,8.4,9.5,10.5,11.8,13.2,15.2,16.6,17.6,19.1,20.5,21.7,23.3,24.7,26.0] {
        try png(frame(t),output.appendingPathComponent(String(format:"v3-%04.1f.png",t)))
    }
    print("Rendered 22 layout and transition samples.")
} else if args.contains("--audit") {
    for scene in scenes {
        let b=inkBounds(scene.title,76)
        precondition(b.width<=1664 && b.height<90,"Heading leaves grid: \(scene.title)")
        precondition(!scene.title.contains("·") && !scene.detail.contains("•"))
        print("\(scene.start)s: \(scene.title) — \(Int(b.width)) px")
    }
    precondition(inkBounds("Ready to use.",51).width<642)
    var letters=Array("nopij ".utf16), glyphs=[CGGlyph](repeating:0,count:6)
    precondition(CTFontGetGlyphsForCharacters(font(100,"ink"),&letters,&glyphs,6),"Fixture font is missing a demonstrated glyph")
    precondition(glyphs.allSatisfy {$0 != 0},"Unexpected font fallback")
    for capture in captures {let im=shots[capture.name]!;precondition(im.width==Int(capture.crop.width) && im.height==Int(capture.crop.height))}
    print("Verified measured headings, seven capture dimensions and explicit workflow sequence. Headlines settle in 240 ms; screens in 380 ms. No opacity fades.")
} else {
    let ffmpeg=Process();ffmpeg.executableURL=URL(fileURLWithPath:"/opt/homebrew/bin/ffmpeg")
    ffmpeg.arguments=["-hide_banner","-loglevel","error","-y","-f","rawvideo","-pixel_format","rgba","-video_size","1920x1080","-framerate","60","-i","pipe:0","-an","-vf","scale=in_range=full:out_range=tv:out_color_matrix=bt709,format=yuv420p","-c:v","libx264","-preset","medium","-crf","16","-pix_fmt","yuv420p","-color_primaries","bt709","-color_trc","bt709","-colorspace","bt709","-movflags","+faststart",output.appendingPathComponent("Typefield-Launch-Master-1080p60-v3.mp4").path]
    let pipe=Pipe();ffmpeg.standardInput=pipe;try ffmpeg.run()
    for i in 0..<Int(duration*Double(fps)) {
        try autoreleasepool {let ctx=frame(Double(i)/Double(fps));try pipe.fileHandleForWriting.write(contentsOf:Data(bytesNoCopy:ctx.data!,count:width*height*4,deallocator:.none))}
        if i%(fps*3)==0 {print("Rendered \(i/fps)s / 27s");fflush(stdout)}
    }
    try pipe.fileHandleForWriting.close();ffmpeg.waitUntilExit();precondition(ffmpeg.terminationStatus==0,"Encoding failed")
    print("Master complete.")
}
