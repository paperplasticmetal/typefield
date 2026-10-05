import AppKit
import CoreText
import Foundation

// Typefield launch film v4. Vector choreography, orthographic planes and shared objects.
// No screenshots are drawn. Product capabilities follow the verified v3 QA round trip.
let args=CommandLine.arguments
let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
let output=root.appendingPathComponent("marketing/launch/renders")
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
let width=1920,height=1080,fps=60,duration=28.0
let rgb=CGColorSpace(name:CGColorSpace.sRGB)!
let paper="F1EEE6",ink="171B1C",dark="121719",muted="88908F",coral="DF805E",blue="96BDC3"
var c:CGContext!
let exportedFont=CGFont(CGDataProvider(url:root.appendingPathComponent("marketing/launch/assets/v3/Ink.ttf") as CFURL)!)!
let icon=NSImage(contentsOf:root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"))!.cgImage(forProposedRect:nil,context:nil,hints:nil)!
func clamp(_ v:Double)->Double {min(1,max(0,v))}
func ease(_ v:Double)->Double {let x=clamp(v);return x*x*x*(x*(x*6-15)+10)}
func progress(_ t:Double,_ a:Double,_ b:Double)->Double {ease((t-a)/(b-a))}
func mix(_ a:Double,_ b:Double,_ p:Double)->Double {a+(b-a)*p}
func color(_ hex:String,_ alpha:Double=1)->CGColor {
 let n=UInt32(hex,radix:16)!
 return CGColor(colorSpace:rgb,components:[Double((n>>16)&255)/255,Double((n>>8)&255)/255,Double(n&255)/255,alpha])!
}
func save(_ f:()->Void){c.saveGState();f();c.restoreGState()}
func layer(_ a:Double,_ f:()->Void){if a<=0{return};save{c.setAlpha(clamp(a));c.beginTransparencyLayer(auxiliaryInfo:nil);f();c.endTransparencyLayer()}}
func transform(_ x:Double,_ y:Double,_ s:Double=1,_ f:()->Void){save{c.translateBy(x:x,y:y);c.scaleBy(x:s,y:s);f()}}
func rect(_ x:Double,_ y:Double,_ w:Double,_ h:Double,_ col:String){c.setFillColor(color(col));c.fill(CGRect(x:x,y:y,width:w,height:h))}
func line(_ x:Double,_ y:Double,_ xx:Double,_ yy:Double,_ col:String,_ w:Double=1){c.setStrokeColor(color(col));c.setLineWidth(w);c.move(to:CGPoint(x:x,y:y));c.addLine(to:CGPoint(x:xx,y:yy));c.strokePath()}
func dot(_ p:CGPoint,_ r:Double,_ col:String){c.setFillColor(color(col));c.fillEllipse(in:CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2))}
func image(_ im:CGImage,_ box:CGRect){save{c.translateBy(x:box.minX,y:box.maxY);c.scaleBy(x:1,y:-1);c.draw(im,in:CGRect(x:0,y:0,width:box.width,height:box.height))}}
var fonts:[String:CTFont]=[:]
func font(_ size:Double,_ face:String="sans")->CTFont {
 let key="\(face)-\(size)";if let f=fonts[key]{return f}
 let names=["sans":"HelveticaNeue","medium":"HelveticaNeue-Medium","serif":"Baskerville","didot":"Didot","futura":"Futura-Medium","mono":"Menlo-Regular"]
 let f=face=="ink" ? CTFontCreateWithGraphicsFont(exportedFont,size,nil,nil):CTFontCreateWithName((names[face] ?? face) as CFString,size,nil)
 fonts[key]=f;return f
}
func typeset(_ s:String,_ size:Double,_ face:String="sans",_ col:String=ink)->CTLine {
 CTLineCreateWithAttributedString(NSAttributedString(string:s,attributes:[.font:font(size,face),.foregroundColor:color(col)]))
}
func bounds(_ s:String,_ size:Double,_ face:String="sans")->CGRect {CTLineGetBoundsWithOptions(typeset(s,size,face),[.useGlyphPathBounds])}
func text(_ s:String,_ x:Double,_ baseline:Double,_ size:Double,_ col:String=ink,_ face:String="sans",_ align:String="left") {
 let l=typeset(s,size,face,col),b=CTLineGetBoundsWithOptions(l,[.useGlyphPathBounds])
 let shift=align=="center" ? -b.midX:(align=="right" ? -b.maxX:-b.minX)
 save{c.textMatrix=CGAffineTransform(scaleX:1,y:-1);c.textPosition=CGPoint(x:x+shift,y:baseline);CTLineDraw(l,c)}
}
func title(_ s:String,_ local:Double,_ light:Bool=true,_ sub:String="") {
 let p=progress(local,0,0.26),col=light ? paper:ink
 save{c.clip(to:CGRect(x:80,y:82,width:1760,height:135));text(s,960,188+120*(1-p),88,col,"sans","center")}
 if !sub.isEmpty {layer(progress(local,0.12,0.28)){text(sub,960,253,28,light ? "A5ADAA":"606866","sans","center")}}
}
let nav=["Library","Spaces","Letterform Editor"]
let navWidths=nav.map{bounds($0,25).width}
let navGap=190.0,navWidth=navWidths.reduce(0,+)+380
let navCenters:[Double]={var edge=960-navWidth/2;return navWidths.map{w in let center=edge+w/2;edge+=w+navGap;return center}}()
func navigation(_ t:Double,_ current:Int,_ light:Bool=true) {
 let col=light ? paper:ink,quiet=light ? "87908E":"767E79"
 for i in 0..<3 {text(nav[i],navCenters[i],1025,25,i==current ? col:quiet,"sans","center")}
 let w=bounds(nav[current],25).width
 rect(navCenters[current]-w/2,1046,w,2,light ? coral:ink)
}
func background(_ light:Bool=false) {
 rect(0,0,1920,1080,light ? paper:dark)
 let colors=[color(light ? "FFFFFF":"2F3A3C",light ? 0.5:0.65),color(light ? paper:dark,0)] as CFArray
 let grad=CGGradient(colorsSpace:rgb,colors:colors,locations:[0,1])!
 c.drawRadialGradient(grad,startCenter:CGPoint(x:1080,y:500),startRadius:0,endCenter:CGPoint(x:1080,y:500),endRadius:1050,options:[])
}
struct Pose {
 var x:Double;var y:Double;var s:Double=1;var yaw:Double=0;var pitch:Double=0;var roll:Double=0
 func toward(_ b:Pose,_ p:Double)->Pose {Pose(x:mix(x,b.x,p),y:mix(y,b.y,p),s:mix(s,b.s,p),yaw:mix(yaw,b.yaw,p),pitch:mix(pitch,b.pitch,p),roll:mix(roll,b.roll,p))}
}
func plane(_ p:Pose,_ f:()->Void){
 save{
  c.translateBy(x:p.x,y:p.y);c.rotate(by:p.roll*Double.pi/180);c.scaleBy(x:p.s,y:p.s)
  let y=p.yaw*Double.pi/180,x=p.pitch*Double.pi/180
  c.concatenate(CGAffineTransform(a:cos(y),b:sin(x)*sin(y),c:0,d:cos(x),tx:0,ty:0));f()
 }
}
func stock(_ w:Double,_ h:Double,_ fill:String,_ shadow:Double=0.26){
 save{c.setShadow(offset:CGSize(width:18,height:28),blur:50,color:color("000000",shadow));rect(-w/2,-h/2,w,h,fill)}
 line(-w/2,-h/2,w/2,-h/2,fill==paper ? "FFFFFF":"EBA386",1.4)
}
func specimen(_ name:String,_ word:String,_ face:String,_ fill:String,_ p:Pose){
 plane(p){stock(560,620,fill);text(name,-230,-248,28,ink,"medium");line(-230,-214,230,-214,"AAAFA8")
 text(word,0,74,face=="ink" ? 240:face=="serif" ? 140:144,ink,face,"center")
 text("Regular",-230,259,22,"5D6662");text("Aa",230,259,24,ink,face,"right")}
}
let cardNames=["Didot","Helvetica Neue","Baskerville","Futura","Menlo"]
let cardFaces=["didot","sans","serif","futura","mono"]
let cardWords=["Ag","Type","Form","Aa","01"]
let cardColors=["D2D8D2","B7C7C5",paper,"DCD3BF","CED0C1"]
func libraryPose(_ i:Int,_ t:Double)->Pose {
 let d=Double(i-2),intro=progress(t,0,0.75),settle=progress(t,0.5,2.1),exit=progress(t,2.65,3.55)
 let base=Pose(x:960+d*500,y:590+abs(d)*42,s:1-abs(d)*0.125,yaw:d*13,pitch:8,roll:d*4)
 return Pose(x:base.x+d*exit*650,y:base.y+105*(1-intro)-settle*14,s:base.s*(1+0.018*settle),yaw:base.yaw+(1-intro)*9,pitch:base.pitch,roll:base.roll)
}
func formLayout(_ w:Double,_ h:Double,_ appear:Double,_ custom:Bool=false){
 let left = -w/2+66,right=w/2-66,top = -h/2+54,bottom=h/2-47
 if custom {
  text("A new sound.",left,top,25);text("Independent music",right,top,24,ink,"sans","right")
  line(left,top+29,right,top+29,"A55843",1)
  text("Live, in good company.",left,bottom,25);text("Friday, 9 pm",right,bottom,25,ink,"sans","right")
 } else {
  layer(appear){text("The shape of ideas",left,top,25);text("Volume 01",right,top,24,ink,"sans","right")
   line(left,top+29,right,top+29,"A3AAA1",1)
   text("& feeling.",left,122,112,ink,"serif")
   line(left,bottom-42,right,bottom-42,"A3AAA1",1)
   text("Typography journal",left,bottom,25);text("A study in contrast",right,bottom,25,ink,"sans","right")
   save{dot(CGPoint(x:350,y:5),166,coral);dot(CGPoint(x:410,y:5),123,ink);dot(CGPoint(x:457,y:5),75,paper)}
  }
 }
}
func opening(_ t:Double){
 background()
 for i in [0,4,1,3] {specimen(cardNames[i],cardWords[i],cardFaces[i],cardColors[i],libraryPose(i,t))}
 let p=progress(t,2.65,4.0),lp=libraryPose(2,min(t,2.65)),target=Pose(x:960,y:615,s:1,yaw:0,pitch:0,roll:0)
 let pose=lp.toward(target,p),w=mix(560,1280,p),h=mix(620,650,p)
 plane(pose){stock(w,h,paper)
  layer(1-p){text("Baskerville",-230,-248,28,ink,"medium");line(-230,-214,230,-214,"AAAFA8");text("Regular",-230,259,22,"5D6662");text("Aa",230,259,24,ink,"serif","right")}
  let wordWidth=bounds("Form",mix(140,224,p),"serif").width
  text("Form",mix(0,-w/2+66+wordWidth/2,p),mix(74,-15,p),mix(140,224,p),ink,"serif","center")
  formLayout(w,h,progress(t,3.55,4.0))
 }
 if t<2.65 {title("Find your type.",t+0.26)}else{title("From Library to Spaces.",t-2.65,true,"Create a typeboard with your chosen fonts.")}
 navigation(t,t<3.35 ? 0:1)
}
func layouts(_ t:Double){
 background()
 let p=progress(t,5.3,6.45),out=progress(t,7.65,8.5)
 let main=Pose(x:mix(960,708,p)-out*500,y:mix(615,612,p),s:mix(1,0.82,p),yaw:mix(0,-8,p),pitch:mix(0,5,p),roll:mix(0,-4,p))
 plane(main){stock(1280,650,paper);text("Form",-574,-15,224,ink,"serif");formLayout(1280,650,1)}
 let second=Pose(x:mix(2350,1470,p)-out*360,y:mix(725,620,p),s:mix(0.72,0.94,p)+out*3.6,yaw:mix(16,-3,p),pitch:4*(1-out),roll:mix(13,7,p)*(1-out))
 plane(second){stock(530,676,coral);text("Type studies.",-217,-269,31);line(-217,-235,217,-235,"A35A43")
 text("F",0,206,510,ink,"serif","center");text("Form in practice.",-217,280,27)}
 layer(1-progress(t,7.65,7.88)){
  if t<5.3 {title("From Library to Spaces.",1,true,"Create a typeboard with your chosen fonts.")}else{title("Put it to work.",t-5.3,true,"Compose with your fonts in Spaces.")}
  navigation(t,1)
 }
}
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
// The macro editing illustration uses the original artwork's smooth stroke outlines.
// The spacing, export and final specimen use the actual app-generated TrueType font.
struct Segment {let kind:CGPathElementType;let points:[CGPoint]}
var character:UniChar=112,glyph:CGGlyph=0
precondition(CTFontGetGlyphsForCharacters(font(1000,"ink"),&character,&glyph,1))
let rawP=CTFontCreatePathForGlyph(font(1000,"ink"),glyph,nil)!,rawBounds=rawP.boundingBoxOfPath
let strokeP=CGMutablePath()
for index in [3,4] {strokeP.addPath(handwritingPaths()[index])}
let smoothP=strokeP.copy(strokingWithWidth:13,lineCap:.round,lineJoin:.round,miterLimit:10)
let smoothBounds=smoothP.boundingBoxOfPath
var norm=CGAffineTransform(a:1/smoothBounds.height,b:0,c:0,d:1/smoothBounds.height,tx:-smoothBounds.midX/smoothBounds.height,ty:-smoothBounds.midY/smoothBounds.height)
let pPath=smoothP.copy(using:&norm)!
var segments:[Segment]=[]
pPath.applyWithBlock{ptr in let e=ptr.pointee;let n=e.type == .addCurveToPoint ? 3:e.type == .addQuadCurveToPoint ? 2:(e.type == .moveToPoint || e.type == .addLineToPoint ? 1:0);segments.append(Segment(kind:e.type,points:Array(UnsafeBufferPointer(start:e.points,count:n))))}
func altered(_ p:CGPoint,_ bend:Double)->CGPoint {
 let influence=max(0,1-abs(p.y+0.19)/0.29)*max(0,1-abs(p.x-0.11)/0.35)
 return CGPoint(x:p.x+bend*influence,y:p.y)
}
func outline(_ bend:Double)->CGPath {
 let path=CGMutablePath()
 for s in segments {let q=s.points.map{altered($0,bend)};switch s.kind {
 case .moveToPoint:path.move(to:q[0])
 case .addLineToPoint:path.addLine(to:q[0])
 case .addQuadCurveToPoint:path.addQuadCurve(to:q[1],control:q[0])
 case .addCurveToPoint:path.addCurve(to:q[2],control1:q[0],control2:q[1])
 case .closeSubpath:path.closeSubpath()
 @unknown default:break
 }}
 return path
}
func vectorP(_ x:Double,_ y:Double,_ h:Double,_ bend:Double,_ control:Double){
 transform(x,y,h){c.setFillColor(color(paper));c.addPath(outline(bend));c.fillPath()}
 layer(control){
  let lowY=y+h/2,topY=y-h/2
  line(300,topY,1620,topY,"3D494A");line(300,lowY,1620,lowY,"3D494A")
  text("x-height",300,topY-15,21,"81908C");text("Descender",300,lowY+34,21,"81908C")
  transform(x,y,h){c.setStrokeColor(color(blue));c.setLineWidth(1.6/h);c.addPath(outline(bend));c.strokePath()}
  var last=CGPoint.zero
  func pos(_ p:CGPoint)->CGPoint{let a=altered(p,bend);return CGPoint(x:x+a.x*h,y:y+a.y*h)}
  var anchorIndex=0
  for s in segments {
   if s.points.isEmpty{continue}
   let end=s.points.last!,point=pos(end)
   if s.kind != .closeSubpath {
    rect(point.x-3.5,point.y-3.5,7,7,dark);c.setStrokeColor(color(blue));c.setLineWidth(1.4);c.stroke(CGRect(x:point.x-3.5,y:point.y-3.5,width:7,height:7))
   }
   if (s.kind == .addQuadCurveToPoint || s.kind == .addCurveToPoint) && end.x>0 && end.y < 0.10 && end.y > -0.40 {
    let handle=pos(s.points[0]),a=pos(last)
    line(a.x,a.y,handle.x,handle.y,coral,1.4);dot(handle,4,coral)
    let other=pos(s.points[s.kind == .addCurveToPoint ? 1:0])
    line(point.x,point.y,other.x,other.y,coral,1.4);dot(other,4,coral);dot(point,4.5,coral)
   }
   last=end;anchorIndex+=1
  }
 }
}
func drawingScene(_ t:Double){
 rect(0,0,1920,1080,coral)
 let local=t-8.5,drawStart=0.14
 title("Make a font of your own.",local,false,"Draw your letters, then import the artwork.")
 let positions=[392.0,807.0,1197.0]
 let paths=[[3,4],[2],[3,4]]
 for i in 0..<3 {
  let origin=i==1 ? 132.0:260.0
  transform(positions[i]+(i==0 ? 0:progress(t,10.6,11.0)*Double(i)*1100),320,3.5){c.translateBy(x:-origin,y:-65);c.setStrokeColor(color(ink));c.setLineWidth(13);c.setLineCap(.round);c.setLineJoin(.round)
   for (j,index) in paths[i].enumerated(){drawStroke(handwriting[index],clamp((local-drawStart-Double(i)*0.35-Double(j)*0.15)/0.32))}
  }
 }
 let scan=progress(local,1.15,1.6)
 layer(scan*(1-progress(t,10.5,10.75))){
  for i in 0..<3 {
   let x=positions[i]-2,y=i==1 ? 324.0:340.0,w=i==1 ? 349.0:332.0,h=i==1 ? 428.0:550.0
   c.setStrokeColor(color("668E91"));c.setLineWidth(1.4);c.stroke(CGRect(x:x,y:y,width:w,height:h))
   text(i==1 ? "o":"p",x+w/2,y+h+39,28,"547A7E","sans","center")
  }
 }
 if local>1.35 && t<10.6{text("Import artwork",960,291,26,ink,"sans","center")}
 navigation(t,2,false)
}
func editing(_ t:Double){
 background()
 let enter=progress(t,11.0,11.6),bend=0.045*(1-progress(t,12.25,13.45))
 let leave=progress(t,14.05,14.5)
 let startX=392+(smoothBounds.midX-260)*3.5,startY=320+(smoothBounds.midY-65)*3.5
 let finalX=960-bounds("pop",630,"ink").midX+rawBounds.midX*0.63-70,finalY=723-rawBounds.midY*0.63
 let h=mix(mix(smoothBounds.height*3.5,610,enter),rawBounds.height*0.63,leave)
 let x=mix(mix(startX,960,enter),finalX,leave),y=mix(mix(startY,595,enter),finalY,leave)
 vectorP(x,y,h,bend,progress(t,11.5,11.8)*(1-leave))
 if leave>0 {layer(leave){kernWord(960+320*(1-leave),723,630,70,paper,1)}}
 if t<14.05 {title("Make every curve yours.",t-11.0,true,"Editable outlines. Precise Bézier control.")}else{title("Down to the space between.",t-14.05)}
 navigation(t,2)
}
func kernWord(_ x:Double,_ baseline:Double,_ size:Double,_ adjustment:Double,_ col:String,_ first:Int=0){
 let f=font(size,"ink"),l=typeset("pop",size,"ink",col),run=(CTLineGetGlyphRuns(l) as! [CTRun])[0]
 var glyphs=[CGGlyph](repeating:0,count:3),positions=[CGPoint](repeating:.zero,count:3)
 CTRunGetGlyphs(run,CFRange(location:0,length:0),&glyphs);CTRunGetPositions(run,CFRange(location:0,length:0),&positions)
 let b=bounds("pop",size,"ink"),left=x-b.midX-adjustment
 for i in first..<3 {if let path=CTFontCreatePathForGlyph(f,glyphs[i],nil){save{c.translateBy(x:left+positions[i].x+Double(i)*adjustment,y:baseline);c.scaleBy(x:1,y:-1);c.setFillColor(color(col));c.addPath(path);c.fillPath()}}}
}
func spacing(_ t:Double){
 background()
 let p=progress(t,14.65,15.65),a=mix(70,0,p)
 title("Down to the space between.",t-14.05)
 kernWord(960,723,630,a,paper)
 let b=bounds("pop",630,"ink")
 let lx=960-b.width/2-a,rx=960+b.width/2+a
 line(lx-26,333,lx-26,864,"4A6263");line(rx+26,333,rx+26,864,"4A6263")
 line(lx-70,742,rx+70,742,"394747")
 text("Spacing and kerning",960,929,28,"A5B2AE","sans","center")
 navigation(t,2)
}
func fileOutline(_ w:Double,_ h:Double,_ fill:String,_ fold:Double){
 let left = -w/2,right=w/2,top = -h/2,bottom=h/2
 let p=CGMutablePath();p.move(to:CGPoint(x:left,y:top));p.addLine(to:CGPoint(x:right-fold,y:top));p.addLine(to:CGPoint(x:right,y:top+fold));p.addLine(to:CGPoint(x:right,y:bottom));p.addLine(to:CGPoint(x:left,y:bottom));p.closeSubpath()
 save{c.setShadow(offset:CGSize(width:15,height:25),blur:35,color:color("000000",0.2));c.setFillColor(color(fill));c.addPath(p);c.fillPath()}
 line(right-fold,top,right-fold,top+fold,"B5BEB5",1.5);line(right-fold,top+fold,right,top+fold,"B5BEB5",1.5)
}
func exportAndReturn(_ t:Double){
 background()
 let p=progress(t,16.65,17.25),returning=progress(t,18.35,19.0)
 for i in [0,4,1,3] {
  let base=libraryPose(i,2.5),pose=Pose(x:base.x+Double(i-2)*600*(1-returning),y:base.y+150*(1-returning),s:base.s,yaw:base.yaw,pitch:base.pitch,roll:base.roll)
  if returning>0 {specimen(cardNames[i],cardWords[i],cardFaces[i],cardColors[i],pose)}
 }
 let w=mix(440,560,returning),h=mix(570,620,returning)
 let position=Pose(x:960,y:590,s:1,yaw:0,pitch:0,roll:0)
 plane(position){
  let reveal=progress(t,16.65,16.95)
  if reveal>0 {transform(0,0,reveal){fileOutline(w,h,paper,58*(1-returning))}}
  layer(progress(t,16.95,17.12)){
   text(returning<0.5 ? "TrueType":"Ink",-w/2+46,-h/2+60,28,ink,"medium")
   text(returning<0.5 ? "Ink.ttf":"Regular",-w/2+46,h/2-44,returning<0.5 ? 32:22,returning<0.5 ? ink:"5D6662")
   if returning>0.5 {text("Aa",w/2-46,h/2-44,24,ink,"sans","right");line(-w/2+46,-h/2+93,w/2-46,-h/2+93,"AAB3A9")}
  }
  kernWord(0,mix(133,55,p),mix(630,236,p),0,paper)
  save{c.clip(to:CGRect(x:-w*reveal/2,y:-h*reveal/2,width:w*reveal,height:h*reveal));kernWord(0,mix(133,55,p),mix(630,236,p),0,ink)}
 }
 if t<18.35 {title("Export your font.",t-16.65,true,"Save an installable TrueType file.")}else{title("Add it to Library.",t-18.35,true,"Export, then add your font folder.")}
 navigation(t,t<18.75 ? 2:0)
}
func finalLayout(_ t:Double){
 background()
 let p=progress(t,20.15,21.15),expand=progress(t,22.4,23.3)
 // Other specimens separate as the same Ink plate becomes the new composition.
 for i in [0,4,1,3] {let base=libraryPose(i,2.5);specimen(cardNames[i],cardWords[i],cardFaces[i],cardColors[i],Pose(x:base.x+Double(i-2)*p*1050,y:base.y,s:base.s,yaw:base.yaw,pitch:base.pitch,roll:base.roll))}
 let w=mix(560,1280,p),h=mix(620,650,p)
 let pose=Pose(x:960,y:590,s:1+expand*0.075,yaw:0,pitch:0,roll:0)
 plane(pose){
  stock(w,h,paper)
  layer(p){rect(-w/2,-h/2,w,h,coral)}
  layer(1-p){text("Ink",-230,-248,28,ink,"medium");text("Regular",-230,259,22,"5D6662")}
  layer(progress(t,20.8,21.2)){formLayout(w,h,1,true)}
  text("pop",0,mix(55,115,p),mix(236,580,p),ink,"ink","center")
 }
 title("Your font, in Spaces.",t-20.15)
 navigation(t,t<20.65 ? 0:1)
}
func ending(_ t:Double){
 background(true)
 let p=progress(t,24.0,24.6)
 let size=mix(330,238,p)
 image(icon,CGRect(x:960-size/2,y:340-size/2,width:size,height:size))
 save{c.clip(to:CGRect(x:360,y:495,width:1200,height:160));text("Typefield",960,617+140*(1-p),124,ink,"medium","center")}
 if t>24.5 {text("Your type, all together.",960,715,38,"646E66","sans","center")}
 for i in 0..<3 {text(nav[i],navCenters[i],857,25,"626B65","sans","center")}
 text("For Mac",960,991,24,"7B837C","sans","center")
}
func frame(_ t:Double)->CGContext {
 let ctx=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:rgb,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 c=ctx;c.translateBy(x:0,y:1080);c.scaleBy(x:1,y:-1);c.setAllowsAntialiasing(true);c.setShouldAntialias(true);c.interpolationQuality = .high
 if t<4 {opening(t)}else if t<8.5 {layouts(t)}else if t<11 {drawingScene(t)}else if t<14.5 {editing(t)}else if t<16.65 {spacing(t)}else if t<20.15 {exportAndReturn(t)}else if t<24 {finalLayout(t)}else{ending(t)}
 return ctx
}
func png(_ ctx:CGContext,_ url:URL)throws {try NSBitmapImageRep(cgImage:ctx.makeImage()!).representation(using:.png,properties:[:])!.write(to:url)}
if let k=args.firstIndex(of:"--frame"),args.count>k+1 {let t=Double(args[k+1])!;try png(frame(t),output.appendingPathComponent(String(format:"v4-%05.2f.png",t)))}
else if args.contains("--stills"){
 for t in [0.0,0.5,1.5,2.6,3.1,3.6,4.3,5.8,6.8,7.8,8.4,8.6,9.3,10.3,10.8,11.2,12.2,13.7,14.7,15.8,16.8,17.4,18.7,19.5,20.4,21.5,23.1,24.2,25.3,27.0]{try png(frame(t),output.appendingPathComponent(String(format:"v4-%05.2f.png",t)))}
 print("Rendered 30 composition and transition frames.")
}else if args.contains("--audit"){
 let headings=["Find your type.","From Library to Spaces.","Put it to work.","Make a font of your own.","Make every curve yours.","Down to the space between.","Export your font.","Add it to Library.","Your font, in Spaces."]
 for h in headings {precondition(bounds(h,88).width<1760);print("Heading: \(h), \(Int(bounds(h,88).width)) px")}
 for i in 0..<3 {let b=bounds(nav[i],25);precondition(navCenters[i]-b.width/2>120 && navCenters[i]+b.width/2<1800)}
 precondition(abs((navCenters[0]-navWidths[0]/2)+(navCenters[2]+navWidths[2]/2)-1920)<0.001)
 var letters=Array("pop".utf16),gs=[CGGlyph](repeating:0,count:3)
 precondition(CTFontGetGlyphsForCharacters(font(100,"ink"),&letters,&gs,3) && gs.allSatisfy{$0>0})
 for t in stride(from:0.0,to:4.0,by:1.0/60){for i in 0..<5{let p=libraryPose(i,t);precondition(p.x.isFinite && p.y.isFinite && p.s>0)}}
 print("Verified optical heading bounds, centered workspace labels, real exported glyphs and 1,200 catalog poses.")
}else{
 let proc=Process();proc.executableURL=URL(fileURLWithPath:"/opt/homebrew/bin/ffmpeg")
 proc.arguments=["-hide_banner","-loglevel","error","-y","-f","rawvideo","-pixel_format","rgba","-video_size","1920x1080","-framerate","60","-i","pipe:0","-an","-vf","scale=in_range=full:out_range=tv:out_color_matrix=bt709,format=yuv420p","-c:v","libx264","-preset","medium","-crf","16","-color_primaries","bt709","-color_trc","bt709","-colorspace","bt709","-movflags","+faststart",output.appendingPathComponent("Typefield-Launch-Master-1080p60-v4.mp4").path]
 let pipe=Pipe();proc.standardInput=pipe;try proc.run()
 for i in 0..<Int(duration*Double(fps)){try autoreleasepool{let ctx=frame(Double(i)/Double(fps));try pipe.fileHandleForWriting.write(contentsOf:Data(bytesNoCopy:ctx.data!,count:width*height*4,deallocator:.none))};if i%(fps*4)==0{print("Rendered \(i/fps)s / 28s");fflush(stdout)}}
 try pipe.fileHandleForWriting.close();proc.waitUntilExit();precondition(proc.terminationStatus==0);print("Master complete.")
}
