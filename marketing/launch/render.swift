import AppKit
import CoreText
import Foundation

// Deterministic motion-design renderer. All dimensions below use a 1920 × 1080pt landscape.
// No production fonts, projects, preferences, or library files are opened.
let args = CommandLine.arguments
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("marketing/launch/renders")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let preview = args.contains("--stills")
let width = 1920
let height = 1080
let fps = 60
let duration = 26.0
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ink = "20242B", paper = "F5F5F2", muted = "797D84", accent = "F06B45"
var c: CGContext!
var omitGlyph = false
func color(_ hex: String, _ alpha: Double = 1) -> CGColor {
    let v = UInt32(hex, radix: 16)!
    return CGColor(colorSpace: space, components: [CGFloat((v >> 16) & 255)/255, CGFloat((v >> 8) & 255)/255, CGFloat(v & 255)/255, alpha])!
}
func clamp(_ x: Double) -> Double { min(1,max(0,x)) }
func smooth(_ x: Double) -> Double { let v=clamp(x); return v*v*(3-2*v) }
func ease(_ x: Double) -> Double { 1-pow(1-clamp(x), 4) }
func mix(_ a: Double, _ b: Double, _ p: Double) -> Double { a+(b-a)*p }
func saved(_ body: () -> Void) { c.saveGState(); body(); c.restoreGState() }
func alpha(_ a: Double, _ body: () -> Void) { saved { c.setAlpha(clamp(a)); body() } }
func transform(_ x: Double, _ y: Double, _ scale: Double=1, _ angle: Double=0, _ body: () -> Void) {
    saved { c.translateBy(x:x,y:y); c.rotate(by:angle); c.scaleBy(x:scale,y:scale); body() }
}
func rect(_ x: Double,_ y: Double,_ w: Double,_ h: Double,_ fill: String,_ radius: Double=0) {
    c.setFillColor(color(fill)); c.addPath(CGPath(roundedRect:CGRect(x:x,y:y,width:w,height:h),cornerWidth:radius,cornerHeight:radius,transform:nil)); c.fillPath()
}
func border(_ x: Double,_ y: Double,_ w: Double,_ h: Double,_ col: String,_ radius: Double=0,_ line: Double=1) {
    c.setStrokeColor(color(col)); c.setLineWidth(line); c.addPath(CGPath(roundedRect:CGRect(x:x,y:y,width:w,height:h),cornerWidth:radius,cornerHeight:radius,transform:nil)); c.strokePath()
}
func line(_ x: Double,_ y: Double,_ x2: Double,_ y2: Double,_ col: String,_ w: Double=1) {
    c.setStrokeColor(color(col));c.setLineWidth(w);c.move(to:CGPoint(x:x,y:y));c.addLine(to:CGPoint(x:x2,y:y2));c.strokePath()
}
func dot(_ x: Double,_ y: Double,_ r: Double,_ col: String) {
    c.setFillColor(color(col));c.fillEllipse(in:CGRect(x:x-r,y:y-r,width:2*r,height:2*r))
}
var fontCache: [String: CTFont] = [:]
func font(_ size: Double,_ weight: String) -> CTFont {
    let key="\(size)-\(weight)"
    if let f=fontCache[key] { return f }
    let name: String
    switch weight { case "bold": name="HelveticaNeue-Bold"; case "medium":name="HelveticaNeue-Medium";case "serif":name="Baskerville";case "italic":name="Baskerville-Italic";case "mono":name="Menlo-Regular";default:name="HelveticaNeue" }
    let f=CTFontCreateWithName(name as CFString,size,nil);fontCache[key]=f;return f
}
func text(_ s: String,_ x: Double,_ y: Double,_ size: Double,_ col: String=ink,_ weight: String="regular",_ align: String="left",_ tracking: Double=0) {
    let attrs: [NSAttributedString.Key:Any] = [.font:font(size,weight),.foregroundColor:color(col),.kern:tracking]
    let l=CTLineCreateWithAttributedString(NSAttributedString(string:s,attributes:attrs))
    let w=CTLineGetTypographicBounds(l,nil,nil,nil)
    let dx = align=="center" ? -w/2 : (align=="right" ? -w : 0)
    saved { c.textMatrix=CGAffineTransform(scaleX:1,y:-1); c.textPosition=CGPoint(x:x+dx,y:y+size*0.81); CTLineDraw(l,c) }
}
func label(_ s: String,_ x: Double,_ y: Double,_ col: String=muted) { text(s,x,y,16,col,"medium","left",2) }
func reveal(_ s: String,_ x: Double,_ y: Double,_ size: Double,_ time: Double,_ col: String=ink,_ weight: String="medium",_ align: String="left") {
    let p=ease(time/0.75)
    saved { c.clip(to:CGRect(x:0,y:y-4,width:1920,height:size*1.3));text(s,x,y+(1-p)*size*1.2,size,col,weight,align) }
}
func pill(_ s: String,_ x: Double,_ y: Double,_ w: Double,_ selected: Bool=false) {
    rect(x,y,w,42,selected ? ink : "E8E9E6",21)
    text(s,x+w/2,y+12,17,selected ? "FFFFFF" : ink,"medium","center")
}
func card(_ x: Double,_ y: Double,_ w: Double,_ h: Double,_ fill: String="FFFFFF",_ radius: Double=22) {
    saved { c.setShadow(offset:CGSize(width:0,height:14),blur:35,color:color("151C27",0.09));rect(x,y,w,h,fill,radius) }
    border(x,y,w,h,"FFFFFF",radius)
}
func chrome(_ w: Double,_ title: String) {
    for i in 0..<3 { dot(24+Double(i)*17,22,4.5,"D0D2D5") }
    text(title,w/2,13,16,muted,"medium","center")
    line(0,45,w,45,"E9EAE8")
}
func image(_ img: CGImage,_ r: CGRect) {
    saved { c.translateBy(x:r.minX,y:r.maxY);c.scaleBy(x:1,y:-1);c.draw(img,in:CGRect(x:0,y:0,width:r.width,height:r.height)) }
}
let iconURL=root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png")
let icon=NSImage(contentsOf:iconURL)!.cgImage(forProposedRect:nil,context:nil,hints:nil)!

// An original geometric demo glyph, with a preserved counter and editable cubic handles.
func glyph(_ bend: Double=0) -> CGPath {
    let p=CGMutablePath()
    p.move(to:CGPoint(x:267,y:70));p.addLine(to:CGPoint(x:320,y:70));p.addLine(to:CGPoint(x:320,y:370));p.addLine(to:CGPoint(x:266,y:370));p.addLine(to:CGPoint(x:266,y:333))
    p.addCurve(to:CGPoint(x:151,y:380),control1:CGPoint(x:239,y:363),control2:CGPoint(x:198,y:380))
    p.addCurve(to:CGPoint(x:14,y:220),control1:CGPoint(x:65-bend,y:380),control2:CGPoint(x:14,y:321))
    p.addCurve(to:CGPoint(x:151,y:60),control1:CGPoint(x:14,y:119),control2:CGPoint(x:65-bend,y:60))
    p.addCurve(to:CGPoint(x:267,y:110),control1:CGPoint(x:201,y:60),control2:CGPoint(x:241,y:79));p.closeSubpath()
    p.move(to:CGPoint(x:266,y:220))
    p.addCurve(to:CGPoint(x:160,y:113),control1:CGPoint(x:266,y:153),control2:CGPoint(x:222,y:113))
    p.addCurve(to:CGPoint(x:69,y:220),control1:CGPoint(x:102,y:113),control2:CGPoint(x:69,y:154))
    p.addCurve(to:CGPoint(x:160,y:327),control1:CGPoint(x:69,y:286),control2:CGPoint(x:102,y:327))
    p.addCurve(to:CGPoint(x:266,y:220),control1:CGPoint(x:222,y:327),control2:CGPoint(x:266,y:287));p.closeSubpath();return p
}
func drawGlyph(_ x: Double,_ y: Double,_ scale: Double,_ col: String=ink,_ bend: Double=0) {
    if omitGlyph { return }
    transform(x,y,scale) { c.setFillColor(color(col));c.addPath(glyph(bend));c.drawPath(using:.eoFill) }
}
func node(_ x: Double,_ y: Double,_ selected: Bool=false) {
    rect(x-5,y-5,10,10,selected ? accent : "FFFFFF",1);border(x-5,y-5,10,10,accent,1,1.6)
}
func editor(_ t: Double,_ compact: Bool=false) {
    rect(0,0,900,590,"FFFFFF",24);chrome(900,"Letterform Editor")
    rect(0,46,60,544,"F7F8F7",0)
    for (i,s) in ["↖","✒","□","○","↔"].enumerated() { if i==0 {rect(11,67,38,38,"EAECE9",8)};text(s,30,76+Double(i)*62,23,i==0 ? accent : muted,"regular","center") }
    for x in stride(from:100.0,through:690.0,by:30) {line(x,83,x,496,"F0F1EE")}
    for y in stride(from:106.0,through:496.0,by:30) {line(84,y,711,y,"F0F1EE")}
    line(84,140,711,140,"D8DDD9");line(84,444,711,444,"BDC6C0")
    text("CAP",98,121,10,muted,"mono");text("BASELINE",98,451,10,muted,"mono")
    let b=sin(smooth((t-1.2)/1.8)*Double.pi)*22
    if !omitGlyph { transform(247,83,0.94) {
        alpha(smooth((t-0.2)/0.8)*0.98) {c.setFillColor(color(ink));c.addPath(glyph(b));c.drawPath(using:.eoFill)}
        alpha(1-smooth((t-0.8)/0.5)*0.55) {
            c.setStrokeColor(color(accent));c.setLineWidth(2);c.setLineDash(phase:-t*150,lengths:[1200*ease(t/1.4),1200]);c.addPath(glyph(b));c.strokePath();c.setLineDash(phase:0,lengths:[])
        }
        alpha(smooth((t-0.4)/0.7)) {
            line(14,220,14,119,accent,1);line(151,60,65-b,60,accent,1);line(151,60,201,60,accent,1)
            for p in [(14.0,220.0),(151,60),(267,110),(320,70),(320,370),(151,380),(266,220),(160,113),(69,220),(160,327)] {node(p.0,p.1)}
            dot(65-b,60,4,accent);dot(201,60,4,accent);dot(14,119,4,accent)
            node(151,60,true)
        }
    }
    }
    line(728,46,728,590,"E9EAE8")
    label("PRECISION",750,84)
    for (i,p) in [("X","151"),("Y","820"),("Smooth","●"),("Kerning","−20")].enumerated() {
        text(p.0,751,128+Double(i)*63,14,muted);rect(750,149+Double(i)*63,127,30,"F1F2EF",6);text(p.1,761,155+Double(i)*63,15,ink,"mono")
    }
    line(60,504,727,504,"E9EAE8")
    for (i,s) in ["a","b","c","d","e","f","g","h"].enumerated() {
        let x=83+Double(i)*78
        if i==0 {rect(x,520,60,54,"EDEFEA",8);drawGlyph(x+17,526,0.075)} else {text(s,x+30,528,36,ink,"regular","center")}
    }
}

func libraryCard(_ name: String,_ style: String,_ x: Double,_ y: Double,_ custom: Bool=false) {
    card(x,y,408,199,custom ? "E8EDE7" : "FFFFFF",18)
    text(name,x+24,y+21,21,ink,"medium");text(custom ? "YOUR FONT" : style,x+383,y+26,11,muted,"medium","right",1)
    if custom {drawGlyph(x+24,y+61,0.30);text("Atelier",x+140,y+97,52,ink,"medium")}
    else {text("Aa Bb Cc",x+23,y+91,62,ink,style=="SERIF" ? "serif" : (style=="MONO" ? "mono" : "regular"))}
    if custom {dot(x+379,y+172,5,accent)}
}
func website(_ x: Double,_ y: Double,_ s: Double) {
    transform(x,y,s) {
        card(0,0,510,535,"FFFFFF",16)
        text("ATELIER",29,26,13,ink,"medium","left",2);text("Objects     About",480,26,11,muted,"regular","right")
        line(28,61,482,61,"E3E5E1")
        text("Made with",30,94,51,ink,"medium");text("character.",30,149,51,ink,"medium")
        text("Considered objects. A different point of view.",31,222,13,muted)
        rect(30,263,450,214,"E4EAE2",7)
        drawGlyph(184,267,0.49,ink)
        text("EXPLORE COLLECTION  ↗",30,500,12,ink,"medium","left",1)
    }
}
func poster(_ x: Double,_ y: Double,_ s: Double) {
    transform(x,y,s) {
        card(0,0,330,470,accent,12)
        text("ATELIER / TYPE STUDIES",24,25,11,"302821","medium","left",1)
        drawGlyph(45,63,0.72,"302821")
        text("A new",23,355,41,"302821","medium");text("perspective.",23,397,41,"302821","medium")
    }
}
func mini(_ x: Double,_ y: Double,_ w: Double,_ title: String,_ kind: Int) {
    card(x,y,w,268,"FFFFFF",19)
    text(title,x+22,y+19,19,ink,"medium")
    line(x,y+56,x+w,y+56,"E6E8E4")
    if kind==0 {
        for yy in stride(from:y+80,through:y+242,by:24) {line(x+17,yy,x+w-17,yy,"E8EBE6")}
        drawGlyph(x+72,y+56,0.46)
        line(x+80,y+84,x+205,y+84,accent);node(x+141,y+84);dot(x+80,y+84,3,accent);dot(x+205,y+84,3,accent)
    } else if kind==1 {
        for i in 0..<3 {let yy=y+73+Double(i)*60;rect(x+16,yy,w-32,49,i==0 ? "E8EDE7":"F4F5F2",8);text(i==0 ? "Atelier" : (i==1 ? "Aa Bb Cc":"Typography"),x+29,yy+11,25,ink,i==1 ? "serif":"regular")}
    } else {
        rect(x+18,y+74,w-36,174,"E4EAE2",8);text("Made with",x+31,y+93,26,ink,"medium");text("character.",x+31,y+124,26,ink,"medium");drawGlyph(x+w-103,y+159,0.18)
    }
}
func opening(_ t: Double) {
    rect(0,0,1920,1080,paper)
    alpha(ease(t/0.5)) {label("TYPEFIELD",100,73,ink);text("MADE FOR MAC",1820,73,16,muted,"medium","right",2)}
    reveal("Good type.",96,303,136,t-0.1)
    reveal("Starts here.",96,451,136,t-0.33)
    let p=ease((t-0.20)/1.35)
    transform(1430,555,mix(1.00,1.90,p),mix(-0.13,0,p)) {
        drawGlyph(-167,-220,1,ink)
        alpha(smooth((t-1.2)/0.7)) {line(-195,-160,170,-160,accent,1);line(-195,150,170,150,accent,1);node(-16,-160);node(153,150)}
    }
    alpha(ease((t-0.7)/0.6)) {text("Find it. Shape it. Put it to work.",103,682,32,muted)}
    alpha(ease((t-0.6)/0.7)) {label("A WORKSPACE FOR TYPOGRAPHY",100,984)}
}
func creation(_ t: Double) {
    rect(0,0,1920,1080,paper)
    label("01 / LETTERFORM EDITOR",100,73)
    reveal("Make it",96,278,116,t)
    reveal("yours.",96,400,116,t-0.12)
    reveal("Draw. Import. Refine.",103,559,31,t-0.2,muted,"regular")
    let enter=ease(t/0.85)
    transform(798+(1-enter)*160,226+(1-enter)*90,1.12,-0.025*(1-enter)) {editor(t)}
    alpha(smooth((t-1)/0.7)) {
        pill("Bézier curves",102,687,212)
        pill("Precision nodes",330,687,234)
        pill("Spacing & kerning",102,748,278)
    }
    alpha(smooth((t-0.8)/0.6)) {label("FROM FIRST SKETCH TO EDITABLE OUTLINE",101,983)}
}
func library(_ t: Double) {
    rect(0,0,1920,1080,paper);label("02 / LIBRARY",100,73)
    reveal("Every font.",96,280,111,t);reveal("In its place.",96,398,111,t-0.13)
    alpha(ease((t-0.35)/0.5)) {text("Your creations. Your collection.",103,562,30,muted)}
    let p=ease(t/0.85)
    transform(854+(1-p)*200,227+(1-p)*90,1.10) {
        libraryCard("Helvetica Neue","SANS",0,0)
        libraryCard("Baskerville","SERIF",436,0)
        libraryCard("Menlo","MONO",436,223)
        let arrive=ease((t-0.35)/0.55)
        alpha(arrive) {transform(0,223+75*(1-arrive),1,0.035*(1-arrive)) {libraryCard("Atelier","",0,0,true)}}
    }
    alpha(smooth((t-0.8)/0.6)) {
        pill("Export .ttf",101,713,190,true)
        text("→",322,719,30,accent,"regular","center")
        pill("Add to Library",358,713,232)
    }
    alpha(smooth((t-1.0)/0.6)) {text("Organize. Preview. Find your next favorite.",1314,765,27,muted,"regular","center");label("A HOME FOR YOUR ENTIRE TYPE COLLECTION",101,983)}
}
func spacesScene(_ t: Double) {
    rect(0,0,1920,1080,"E8EDE7");label("03 / SPACES",100,73)
    reveal("Type comes",96,279,105,t);reveal("to life.",96,392,105,t-0.13)
    alpha(ease((t-0.3)/0.7)) {text("Build typeboards.",103,547,31,muted);text("Explore real layouts.",103,590,31,muted)}
    let p=ease(t/1.0)
    transform(802+(1-p)*120,240+(1-p)*180,1.12,-0.028*(1-p)) {website(0,0,1)}
    transform(1450+(1-p)*190,317+(1-p)*120+sin(t*0.8)*5,1.10,0.04*(1-p)) {poster(0,0,1)}
    alpha(ease((t-1.0)/0.7)) {
        transform(1230,174+sin(t)*4) {
            card(0,0,403,89,"FFFFFF",15)
            text("DISPLAY FONT",22,16,11,muted,"medium","left",1)
            text("Atelier",22,38,29,ink,"medium")
            dot(365,45,16,"E8EDE7");text("✓",365,33,23,ink,"regular","center")
        }
    }
    alpha(smooth((t-2.2)/0.6)) {pill("Your font, in context",101,709,318,true);label("ONE FONT. EVERY POSSIBILITY.",101,983)}
}
func flow(_ t: Double) {
    rect(0,0,1920,1080,paper);label("CONNECTED BY DESIGN",100,73)
    reveal("Three spaces. One creative flow.",960,190,94,t,ink,"medium","center")
    let titles=["Letterform Editor","Library","Spaces"]
    for i in 0..<3 {
        let p=ease((t-Double(i)*0.12)/0.85)
        alpha(p) {transform(210+Double(i)*550,407+(1-p)*130,1.33) {mini(0,0,300,titles[i],i)}}
    }
    let p=smooth((t-0.7)/1.5)
    line(410,835,1510,835,"D6DAD3",2)
    line(410,835,410+1100*p,835,accent,2)
    for i in 0..<3 {let x=410+Double(i)*550;dot(x,835,9,p>=Double(i)/2 ? accent:"D6DAD3");text(["CREATE","COLLECT","COMPOSE"][i],x,879,17,muted,"medium","center",2)}
    alpha(smooth((t-1.6)/0.5)) {text("From your first curve to your next big idea.",960,978,28,muted,"regular","center")}
}
func end(_ t: Double) {
    rect(0,0,1920,1080,ink)
    let p=ease(t/0.95)
    transform(634,502+(1-p)*90,mix(0.80,1,p)) {
        saved {c.setShadow(offset:CGSize(width:0,height:26),blur:60,color:color("000000",0.35));image(icon,CGRect(x:-158,y:-158,width:316,height:316))}
    }
    reveal("Typefield",855,395,133,t-0.15,"F5F5F2","medium")
    alpha(ease((t-0.48)/0.65)) {text("Make type. Make it yours.",864,568,38,"BFC5CB")}
    alpha(ease((t-0.95)/0.65)) {line(898,779,1022,779,"646D76");text("YOUR TYPOGRAPHY WORKSPACE",960,836,18,"BFC5CB","medium","center",2);text("Made for Mac.",960,888,24,"BFC5CB","regular","center")}
}
let starts=[0.0,3.3,8.3,12.7,18.3,22.1]
let scenes:[(Double)->Void]=[opening,creation,library,spacesScene,flow,end]
func frame(_ time: Double) -> CGContext {
    let ctx=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    c=ctx;c.translateBy(x:0,y:Double(height));c.scaleBy(x:Double(width)/1920,y:-Double(height)/1080)
    c.setAllowsAntialiasing(true);c.setShouldAntialias(true)
    let idx=starts.lastIndex(where:{$0<=time}) ?? 0
    let local=time-starts[idx]
    // The hero glyph physically travels from introduction to editor to library.
    // Draw whole scenes into transparency layers so their internal alpha is preserved.
    if (idx==1 || idx==2) && local<0.95 {
        let p=smooth(local/0.95)
        rect(0,0,1920,1080,paper)
        omitGlyph=true
        saved {
            c.setAlpha(1-smooth(local/0.32));c.beginTransparencyLayer(auxiliaryInfo:nil)
            scenes[idx-1](time-starts[idx-1]);c.endTransparencyLayer()
        }
        saved {
            c.setAlpha(smooth((local-0.34)/0.46));c.beginTransparencyLayer(auxiliaryInfo:nil)
            scenes[idx](local);c.endTransparencyLayer()
        }
        omitGlyph=false
        let from=idx==1 ? (1112.7,137.0,1.90) : (1074.64,318.96,1.0528)
        let to=idx==1 ? (1074.64,318.96,1.0528) : (880.4,539.4,0.33)
        drawGlyph(mix(from.0,to.0,p),mix(from.1,to.1,p)-sin(p*Double.pi)*60,mix(from.2,to.2,p))
    } else if idx>0 && local<0.48 {
        scenes[idx-1](time-starts[idx-1])
        let p=ease(local/0.48)
        saved {c.clip(to:CGRect(x:1920*(1-p),y:0,width:1920*p,height:1080));c.translateBy(x:50*(1-p),y:0);scenes[idx](local)}
    } else {scenes[idx](local)}
    return ctx
}
func savePNG(_ ctx: CGContext,_ url: URL) throws {
    let rep=NSBitmapImageRep(cgImage:ctx.makeImage()!)
    try rep.representation(using:.png,properties:[:])!.write(to:url)
}
if preview {
    for t in [0.8,2.6,4.5,6.8,9.8,11.8,14.6,17.1,20.6,24.7] {
        try savePNG(frame(t),output.appendingPathComponent(String(format:"frame-%04.1f.png",t)))
    }
    print("Rendered 10 storyboard stills.")
} else {
    let ffmpeg=Process();ffmpeg.executableURL=URL(fileURLWithPath:"/opt/homebrew/bin/ffmpeg")
    ffmpeg.arguments=["-hide_banner","-loglevel","error","-y","-f","rawvideo","-pixel_format","rgba","-video_size","\(width)x\(height)","-framerate","\(fps)","-i","pipe:0","-an","-vf","scale=in_range=full:out_range=tv:out_color_matrix=bt709,format=yuv420p","-c:v","libx264","-preset","medium","-crf","16","-pix_fmt","yuv420p","-color_primaries","bt709","-color_trc","bt709","-colorspace","bt709","-movflags","+faststart",output.appendingPathComponent("Typefield-Launch-Master-1080p60.mp4").path]
    let pipe=Pipe();ffmpeg.standardInput=pipe;try ffmpeg.run()
    for i in 0..<Int(duration*Double(fps)) {
        try autoreleasepool {
            let ctx=frame(Double(i)/Double(fps))
            try pipe.fileHandleForWriting.write(contentsOf:Data(bytesNoCopy:ctx.data!,count:width*height*4,deallocator:.none))
        }
        if i % (fps*2)==0 {print("Rendered \(i/fps)s / 26s");fflush(stdout)}
    }
    try pipe.fileHandleForWriting.close();ffmpeg.waitUntilExit()
    guard ffmpeg.terminationStatus==0 else {fatalError("Encoding failed")}
    print("Master complete.")
}
