import AppKit
import CoreText
import Foundation

// Landscape film, revision 2. A single outline moves through one continuous timeline.
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
func phrase(_ lines:[String],_ x:Double,_ baseline:Double,_ size:Double,_ leading:Double,_ t:Double,_ start:Double,_ finish:Double) {
    let leave=1-progress(t,finish-0.45,finish)
    for (i,s) in lines.enumerated() {
        let p=progress(t,start+Double(i)*0.09,start+0.85+Double(i)*0.09)
        layer(p*leave) {text(s,x,baseline+Double(i)*leading+18*(1-p),size)}
    }
}
func sheet(_ x:Double,_ y:Double,_ w:Double,_ h:Double,_ col:String) {
    save { c.setShadow(offset:CGSize(width:0,height:12),blur:38,color:color("22241F",0.075));rect(x,y,w,h,col) }
}
func image(_ img:CGImage,_ r:CGRect) {
    save { c.translateBy(x:r.minX,y:r.maxY);c.scaleBy(x:1,y:-1);c.draw(img,in:CGRect(x:0,y:0,width:r.width,height:r.height)) }
}
let icon=NSImage(contentsOf:root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"))!.cgImage(forProposedRect:nil,context:nil,hints:nil)!

// Use one real specimen outline throughout, including its actual curve anchors.
// Futura is a local typographic stand-in for the fictional Atelier project; no font is bundled.
let specimenFont=font(1000,"specimen")
var aChar:UniChar=97
var aGlyph:CGGlyph=0
precondition(CTFontGetGlyphsForCharacters(specimenFont,&aChar,&aGlyph,1))
let rawGlyph=CTFontCreatePathForGlyph(specimenFont,aGlyph,nil)!
let rawBounds=rawGlyph.boundingBoxOfPath
var normalization=CGAffineTransform(a:1/rawBounds.height,b:0,c:0,d:-1/rawBounds.height,tx:-rawBounds.minX/rawBounds.height,ty:rawBounds.maxY/rawBounds.height)
let baseGlyph=rawGlyph.copy(using: &normalization)!
struct Segment { let type:CGPathElementType; let points:[CGPoint] }
var segments:[Segment]=[]
baseGlyph.applyWithBlock { e in
    let el=e.pointee
    let n:Int
    switch el.type {case .moveToPoint,.addLineToPoint:n=1;case .addQuadCurveToPoint:n=2;case .addCurveToPoint:n=3;default:n=0}
    segments.append(Segment(type:el.type,points:Array(UnsafeBufferPointer(start:el.points,count:n))))
}
func adjusted(_ p:CGPoint,_ bend:Double) -> CGPoint {
    // A restrained shoulder correction settles back to the exact specimen outline.
    let influence=max(0,1-p.y/0.42)
    return CGPoint(x:p.x+bend*influence*sin(p.x*Double.pi),y:p.y)
}
func path(_ bend:Double) -> CGPath {
    let p=CGMutablePath()
    for s in segments {
        let a=s.points.map {adjusted($0,bend)}
        switch s.type {
        case .moveToPoint:p.move(to:a[0])
        case .addLineToPoint:p.addLine(to:a[0])
        case .addQuadCurveToPoint:p.addQuadCurve(to:a[1],control:a[0])
        case .addCurveToPoint:p.addCurve(to:a[2],control1:a[0],control2:a[1])
        case .closeSubpath:p.closeSubpath()
        @unknown default:break
        }
    }
    return p
}
struct Pose {
    let x:Double,y:Double,h:Double
    func interpolate(_ b:Pose,_ p:Double) -> Pose {Pose(x:mix(x,b.x,p),y:mix(y,b.y,p),h:mix(h,b.h,p))}
}
func firstLetterPose(_ x:Double,_ baseline:Double,_ size:Double) -> Pose {
    Pose(x:x+rawBounds.minX*size/1000,y:baseline-rawBounds.maxY*size/1000,h:rawBounds.height*size/1000)
}
func specimen(_ s:String,_ x:Double,_ baseline:Double,_ size:Double,_ col:String=ink,_ omitFirst:Bool=false) {
    let l=typeset(s,size,"specimen",col)
    let runs=CTLineGetGlyphRuns(l) as! [CTRun]
    var index=0
    for run in runs {
        let count=CTRunGetGlyphCount(run)
        var glyphs=[CGGlyph](repeating:0,count:count), positions=[CGPoint](repeating:.zero,count:count)
        CTRunGetGlyphs(run,CFRange(location:0,length:0),&glyphs)
        CTRunGetPositions(run,CFRange(location:0,length:0),&positions)
        for i in 0..<count {
            defer {index+=1}
            if omitFirst && index==0 {continue}
            if let p=CTFontCreatePathForGlyph(font(size,"specimen"),glyphs[i],nil) {
                save { c.translateBy(x:x+positions[i].x,y:baseline-positions[i].y);c.scaleBy(x:1,y:-1);c.setFillColor(color(col));c.addPath(p);c.fillPath() }
            }
        }
    }
}
let libraryPose=firstLetterPose(923,576,140)
func boardPose(_ t:Double) -> (Double,Double,Double) {
    let p=progress(t,14.2,16.9)
    return (mix(410,190,p),mix(269,292,p),mix(1,0.88,p))
}
func boardGlyph(_ t:Double) -> Pose {
    let b=boardPose(t),p=firstLetterPose(58,345,251)
    return Pose(x:b.0+p.x*b.2,y:b.1+p.y*b.2,h:p.h*b.2)
}
func heroPose(_ t:Double) -> Pose {
    let opening=Pose(x:1205,y:280,h:520)
    let edit=Pose(x:1145,y:248,h:576)
    if t<3.8 {return opening.interpolate(edit,progress(t,2.5,3.8))}
    if t<8.05 {return edit.interpolate(libraryPose,progress(t,6.6,8.05))}
    if t<12.7 {return libraryPose.interpolate(boardGlyph(12.7),progress(t,11.1,12.7))}
    if t<20.05 {return boardGlyph(t)}
    let summary=Pose(x:792,y:345,h:350)
    if t<21.15 {return boardGlyph(20.05).interpolate(summary,progress(t,20.05,21.15))}
    return summary.interpolate(Pose(x:921,y:325,h:112),progress(t,22.1,23.35))
}
func drawHero(_ pose:Pose,_ bend:Double,_ opacity:Double=1) {
    layer(opacity) {transform(pose.x,pose.y,pose.h) {c.setFillColor(color(ink));c.addPath(path(bend));c.fillPath()}}
}
func controls(_ pose:Pose,_ bend:Double,_ opacity:Double) {
    layer(opacity) {
        let left=pose.x-115,right=pose.x+pose.h*baseGlyph.boundingBoxOfPath.width+115
        line(left,pose.y,right,pose.y,"BFC3BA")
        line(left,pose.y+pose.h,right,pose.y+pose.h,"BFC3BA")
        func screen(_ p:CGPoint)->CGPoint {let a=adjusted(p,bend);return CGPoint(x:pose.x+a.x*pose.h,y:pose.y+a.y*pose.h)}
        var last=CGPoint.zero
        var first=CGPoint.zero
        c.setStrokeColor(color(accent));c.setLineWidth(1.2)
        transform(pose.x,pose.y,pose.h) {c.setLineWidth(1.2/pose.h);c.addPath(path(bend));c.strokePath()}
        for s in segments {
            let a=s.points
            if s.type == .moveToPoint {last=a[0];first=last}
            if s.type == .addCurveToPoint || s.type == .addQuadCurveToPoint {
                let end=a.last!,one=screen(last),two=screen(a[0]),three=screen(end),four=screen(a[a.count-2])
                // Only expose the upper shoulder's handles. Other anchors remain quiet.
                if last.y<0.35 || end.y<0.35 {
                    line(one.x,one.y,two.x,two.y,accent,1.1);dot(two,3.2,accent)
                    line(three.x,three.y,four.x,four.y,accent,1.1);dot(four,3.2,accent)
                }
                last=end
            } else if s.type == .addLineToPoint {last=a[0]}
            else if s.type == .closeSubpath {last=first;continue}
            let p=screen(last)
            rect(p.x-3.6,p.y-3.6,7.2,7.2,paper)
            c.setStrokeColor(color(accent));c.setLineWidth(1.2);c.stroke(CGRect(x:p.x-3.6,y:p.y-3.6,width:7.2,height:7.2))
        }
    }
}
func collection(_ t:Double) {
    let a=progress(t,7.5,8.5)*(1-progress(t,11.2,12.35))
    layer(a) {
        transform(0,0) {
            text("Library",923,229,27,quiet)
            line(923,273,1784,273,"CFD2C9")
            text("Baskerville",923,398,94,ink,"serif")
            line(923,438,1784,438,"DDDFD7")
            layer(progress(t,8.05,8.65)) {specimen("atelier",923,576,140,ink,true)}
            line(923,622,1784,622,"DDDFD7")
            text("Helvetica Neue",923,739,79)
            line(923,791,1784,791,"CFD2C9")
            layer(progress(t,8.9,9.8)) {text("Atelier · your font",1784,584,23,quiet,"sans","right")}
        }
    }
}
func editorial(_ t:Double) {
    let a=progress(t,11.6,12.7)*(1-progress(t,19.2,20.05))
    let b=boardPose(t)
    layer(a) {transform(b.0,b.1,b.2) {
        sheet(0,0,1100,630,"FAF9F5")
        text("Atelier journal",61,82,25)
        text("Issue 01",1039,82,22,quiet,"sans","right")
        line(60,112,1040,112,"CFD2C9")
        layer(progress(t,12.7,13.3)) {specimen("atelier",58,345,251,ink,true)}
        line(60,404,1040,404,"CFD2C9")
        text("Notes on type,",61,468,29)
        text("from sketch to screen.",61,507,29)
        text("Autumn 2026",1039,502,25,quiet,"italic","right")
        text("01",1039,570,24,quiet,"sans","right")
    }}
    let p=progress(t,15.1,17.2)
    layer(a*p) {transform(1250+120*(1-p),250+24*(1-p)) {
        sheet(0,0,436,683,"C9D0BD")
        text("Type in",37,91,44)
        text("practice.",37,142,44)
        let small=Pose(x:66,y:211,h:315)
        drawHero(small,0)
        line(37,580,399,580,"87907E")
        text("Atelier",38,632,27,ink,"specimen")
        text("02",399,632,23,ink,"sans","right")
    }}
}
func openingAndEditing(_ t:Double) {
    phrase(["It starts with","a letter."],128,467,96,108,t,-0.55,3.2)
    phrase(["Give it","character."],128,455,96,108,t,3.15,7.05)
    layer(progress(t,4.4,5.2)*(1-progress(t,6.5,7.05))) {
        text("Letterform Editor",131,699,29)
        text("Bézier curves, spacing and kerning.",131,745,27,quiet)
    }
}
func libraryCopy(_ t:Double) {
    phrase(["Your font.","Your library."],128,455,96,108,t,7.25,11.65)
    layer(progress(t,9.0,9.8)*(1-progress(t,11.15,11.65))) {
        text("Export your font.",131,703,28,quiet)
        text("Add it to Library.",131,743,28,quiet)
    }
}
func spacesCopy(_ t:Double) {
    let a=progress(t,12.1,13.1)*(1-progress(t,18.9,19.5))
    layer(a) {text("Put your type to work.",960,166,68,ink,"sans","center")}
    layer(progress(t,16.3,17.2)*(1-progress(t,19,19.5))) {
        text("Explore layouts in Spaces.",960,994,28,quiet,"sans","center")
    }
}
func summary(_ t:Double) {
    layer(progress(t,20.2,21.0)*(1-progress(t,22.15,22.8))) {
        text("Three spaces. One flow.",960,214,68,ink,"sans","center")
    }
    layer(progress(t,20.8,21.5)*(1-progress(t,22.25,22.8))) {
        let words=["Letterform Editor","→","Library","→","Spaces"]
        let widths=words.map {inkBounds($0,26).width}
        let total=widths.reduce(0,+)+36*Double(words.count-1)
        var x=960-total/2
        for (i,word) in words.enumerated() {
            text(word,x,815,26,i%2==1 ? quiet:ink)
            x+=widths[i]+36
        }
    }
}
func closing(_ t:Double) {
    let a=progress(t,22.8,23.65)
    layer(a) {
        let s=mix(0.95,1,progress(t,22.8,24.1))
        transform(960,373,s) {image(icon,CGRect(x:-113,y:-113,width:226,height:226))}
    }
    layer(progress(t,23.25,24.15)) {text("Typefield",960,643,116,ink,"medium","center")}
    layer(progress(t,23.65,24.45)) {text("Make it your own.",960,733,34,quiet,"sans","center")}
    layer(progress(t,24.05,24.75)) {text("For Mac",960,905,24,quiet,"sans","center")}
}
func frame(_ t:Double) -> CGContext {
    let ctx=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:rgb,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    c=ctx;c.translateBy(x:0,y:Double(height));c.scaleBy(x:1,y:-1)
    c.setAllowsAntialiasing(true);c.setShouldAntialias(true)
    rect(0,0,1920,1080,paper)
    openingAndEditing(t);libraryCopy(t);collection(t);editorial(t);spacesCopy(t);summary(t)
    let pose=heroPose(t)
    let bend=0.075*(1-progress(t,4.1,6.2))
    drawHero(pose,bend,1-progress(t,22.75,23.4))
    controls(pose,bend,progress(t,1.4,2.35)*(1-progress(t,6.35,7.15)))
    closing(t)
    return ctx
}
func png(_ ctx:CGContext,_ url:URL) throws {
    try NSBitmapImageRep(cgImage:ctx.makeImage()!).representation(using:.png,properties:[:])!.write(to:url)
}
if args.contains("--stills") {
    for t in [1.2,2.4,3.05,3.55,4.2,5.7,6.8,7.5,7.9,8.2,8.7,10.2,11.8,12.5,12.8,13.4,15.3,17.8,19.6,20.2,20.8,21.5,22.5,23.3,25.4] {
        try png(frame(t),output.appendingPathComponent(String(format:"v2-%04.1f.png",t)))
    }
    print("Rendered 25 timing and layout frames.")
} else if args.contains("--audit") {
    let checks:[(String,Double,String)] = [("It starts with",96,"sans"),("a letter.",96,"sans"),("Give it",96,"sans"),("character.",96,"sans"),("Your font.",96,"sans"),("Your library.",96,"sans"),("Three spaces. One flow.",68,"sans"),("Put your type to work.",68,"sans"),("Typefield",116,"medium")]
    for (s,size,face) in checks {
        let b=inkBounds(s,size,face)
        precondition(b.width<1700 && b.height<size*1.25)
        print("\(s): ink \(String(format:"%.2f × %.2f",b.width,b.height)), cap \(String(format:"%.2f",CTFontGetCapHeight(font(size,face))))")
    }
    for i in 0..<Int(duration*Double(fps)) {
        let t=Double(i)/Double(fps),p=heroPose(t)
        precondition(p.x.isFinite && p.y.isFinite && p.h.isFinite && p.h>0)
        precondition(p.x>=96 && p.x+p.h*baseGlyph.boundingBoxOfPath.width<=1824)
        precondition(p.y>=128 && p.y+p.h<=936)
    }
    for time in [2.5,3.8,6.6,8.05,11.1,12.7,14.2,16.9,20.05,21.15,22.1,23.35] {
        let a=heroPose(time-0.00001),b=heroPose(time+0.00001)
        precondition(abs(a.x-b.x)<0.05 && abs(a.y-b.y)<0.05 && abs(a.h-b.h)<0.05,"Discontinuous outline at \(time)")
    }
    for size in [140.0,251.0] {
        let native=CTFontCreatePathForGlyph(font(size,"specimen"),aGlyph,nil)!.boundingBoxOfPath
        precondition(abs(native.height-rawBounds.height*size/1000)<0.01)
        precondition(abs(native.minX-rawBounds.minX*size/1000)<0.01)
    }
    print("Verified 1,620 outline positions, 12 transition joins and both word-baseline matches.")
    print("Specimen: \(CTFontCopyPostScriptName(specimenFont)); outline elements: \(segments.count).")
} else {
    let ffmpeg=Process();ffmpeg.executableURL=URL(fileURLWithPath:"/opt/homebrew/bin/ffmpeg")
    ffmpeg.arguments=["-hide_banner","-loglevel","error","-y","-f","rawvideo","-pixel_format","rgba","-video_size","1920x1080","-framerate","60","-i","pipe:0","-an","-vf","scale=in_range=full:out_range=tv:out_color_matrix=bt709,format=yuv420p","-c:v","libx264","-preset","medium","-crf","16","-pix_fmt","yuv420p","-color_primaries","bt709","-color_trc","bt709","-colorspace","bt709","-movflags","+faststart",output.appendingPathComponent("Typefield-Launch-Master-1080p60-v2.mp4").path]
    let pipe=Pipe();ffmpeg.standardInput=pipe;try ffmpeg.run()
    for i in 0..<Int(duration*Double(fps)) {
        try autoreleasepool {let ctx=frame(Double(i)/Double(fps));try pipe.fileHandleForWriting.write(contentsOf:Data(bytesNoCopy:ctx.data!,count:width*height*4,deallocator:.none))}
        if i%(fps*3)==0 {print("Rendered \(i/fps)s / 27s");fflush(stdout)}
    }
    try pipe.fileHandleForWriting.close();ffmpeg.waitUntilExit();precondition(ffmpeg.terminationStatus==0,"Encoding failed")
    print("Master complete.")
}
