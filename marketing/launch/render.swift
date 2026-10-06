import AppKit
import CoreText
import Foundation

// Typefield launch film v16. Vector choreography, orthographic planes and shared objects.
// No screenshots are drawn. Product capabilities follow the verified v3 QA round trip.
let args=CommandLine.arguments
let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
let output=root.appendingPathComponent("marketing/launch/renders")
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
let width=1920,height=1080,fps=60,duration=59.5
let rgb=CGColorSpace(name:CGColorSpace.sRGB)!
let paper="F7F7F5",ink="222326",stage="FFFFFF",muted="696B70",coral="DF805E",blue="2F6570"
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
func blendedHex(_ a:String,_ b:String,_ p:Double)->String {
 let aa=UInt32(a,radix:16)!,bb=UInt32(b,radix:16)!
 let values=[16,8,0].map{shift in Int(mix(Double((aa>>shift)&255),Double((bb>>shift)&255),clamp(p)).rounded())}
 return String(format:"%02X%02X%02X",values[0],values[1],values[2])
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
 let p=progress(local,0,0.34),col=ink
 if local>0 {captionTop=sub.isEmpty ? 230:280}
 layer(p){text(s,960,188+22*(1-p),88,col,"medium","center")}
 if !sub.isEmpty {layer(progress(local,0.14,0.36)){text(sub,960,253,28,muted,"sans","center")}}
}
let nav=["Library","Spaces","Letterform Editor"]
let navWidths=nav.map{bounds($0,25).width}
// Three equal 380 px columns. Spaces lies on the frame's center axis.
let navCenters=[580.0,960.0,1340.0]
func navigation(_ t:Double,_ current:Int,_ light:Bool=true) {
 let col=ink,quiet=muted
 navVisible=true
 for i in 0..<3 {text(nav[i],navCenters[i],1025,25,i==current ? col:quiet,"sans","center")}
 let w=bounds(nav[current],25).width
 rect(navCenters[current]-w/2,1046,w,2,ink)
}
func background(_ light:Bool=false) {rect(0,0,1920,1080,stage)}
// Capture transformed surfaces from the same drawing commands used in the film.
var paperBounds:[CGRect]=[],navVisible=false,captionTop=230.0
func recordPaper(_ box:CGRect){
 let device=box.applying(c.ctm)
 paperBounds.append(CGRect(x:device.minX,y:1080-device.maxY,width:device.width,height:device.height))
}
func validateGeometry(_ t:Double){
 for box in paperBounds where box.maxX>0 && box.minX<1920 {
  if navVisible && box.maxY>948.1 {fputs("Footer collision at \(t): \(box)\n",stderr);exit(1)}
  if box.minY<captionTop-0.1 {fputs("Caption collision at \(t): \(box), expected \(captionTop)\n",stderr);exit(1)}
 }
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
func planeBounds(_ pose:Pose,_ w:Double,_ h:Double)->CGRect {
 let yaw=pose.yaw*Double.pi/180,pitch=pose.pitch*Double.pi/180,roll=pose.roll*Double.pi/180
 let corners=[(-w/2,-h/2),(w/2,-h/2),(-w/2,h/2),(w/2,h/2)].map {x,y -> CGPoint in
  let ox=cos(yaw)*x,oy=sin(pitch)*sin(yaw)*x+cos(pitch)*y
  return CGPoint(x:pose.x+pose.s*(ox*cos(roll)-oy*sin(roll)),y:pose.y+pose.s*(ox*sin(roll)+oy*cos(roll)))
 }
 let xs=corners.map{$0.x},ys=corners.map{$0.y}
 return CGRect(x:xs.min()!,y:ys.min()!,width:xs.max()!-xs.min()!,height:ys.max()!-ys.min()!)
}
func stock(_ w:Double,_ h:Double,_ fill:String,_ shadow:Double=0.12){
 recordPaper(CGRect(x:-w/2,y:-h/2,width:w,height:h))
 save{c.setShadow(offset:CGSize(width:8,height:-12),blur:24,color:color("000000",shadow));rect(-w/2,-h/2,w,h,fill)}
}
func specimen(_ name:String,_ word:String,_ face:String,_ fill:String,_ p:Pose){
 plane(p){stock(560,620,fill);text(name,-230,-248,28,ink,"medium");line(-230,-214,230,-214,"C5C8CD")
 text(word,0,74,face=="ink" ? 240:140,ink,face,"center")
 text("Regular",-230,259,22,muted);text("Aa",230,259,24,ink,face,"right")}
}
let cardNames=["Didot","Helvetica Neue","Baskerville","Futura","Menlo"]
let cardFaces=["didot","sans","serif","futura","mono"]
let cardWords=Array(repeating:"Form",count:5)
let cardColors=Array(repeating:paper,count:5)
func libraryPose(_ i:Int,_ t:Double)->Pose {
 let d=Double(i-2),intro=progress(t,0,0.75),settle=progress(t,0.5,2.1),exit=progress(t,2.65,3.55)
 let base=Pose(x:960+d*500,y:590+abs(d)*42+(i==2 ? 20:0),s:1-abs(d)*0.125,yaw:d*13,pitch:8,roll:d*4)
 return Pose(x:base.x+d*exit*650,y:base.y-48*(1-intro)-settle*14,s:base.s*(1+0.018*settle),yaw:base.yaw+(1-intro)*9,pitch:base.pitch,roll:base.roll)
}
func formLayout(_ w:Double,_ h:Double,_ appear:Double,_ custom:Bool=false){
 let left = -w/2+66,right=w/2-66,top = -h/2+54,bottom=h/2-47
 if custom {
  text("A new sound",left,top,25);text("Independent music",right,top,24,ink,"sans","right")
  line(left,top+29,right,top+29,"A55843",1)
  text("Live, in good company.",left,bottom,25);text("Friday, 9 pm",right,bottom,25,ink,"sans","right")
 } else {
  layer(appear){text("The shape of ideas",left,top,25);text("Volume 01",right,top,24,ink,"sans","right")
   line(left,top+29,right,top+29,"C5C8CD",1)
   text("& feeling",left,122,112,ink,"serif")
   line(left,bottom-42,right,bottom-42,"C5C8CD",1)
   text("Typography journal",left,bottom,25);text("A study in contrast",right,bottom,25,ink,"sans","right")
   save{dot(CGPoint(x:350,y:5),166,coral);dot(CGPoint(x:410,y:5),123,ink);dot(CGPoint(x:457,y:5),75,paper)}
  }
 }
}
func sortedPose(_ i:Int,_ t:Double)->Pose {
 let order=[1.0,3.0,0.0,2.0,4.0],p=progress(t,0.8,2.0),slot=mix(Double(i),order[i],p),d=slot-2
 return Pose(x:960+d*380,y:625+abs(d)*12-24*(1-progress(t,0,0.7)),s:0.69-abs(d)*0.02,yaw:d*5,pitch:3,roll:d*2)
}
func collectionPose(_ i:Int)->Pose {
 let xs=[960.0,1365.0,555.0,2400.0,2800.0]
 return Pose(x:xs[i],y:660,s:0.65,yaw:0,pitch:0,roll:0)
}
func shortlistPose(_ i:Int)->Pose {
 Pose(x:i==2 ? 620:1300,y:615,s:0.93,yaw:0,pitch:0,roll:0)
}
func shortlistMark(_ pose:Pose,_ a:Double){
 layer(a){plane(pose){
  line(198,-268,211,-255,blue,3);line(211,-255,235,-284,blue,3)
 }}
}
func libraryStory(_ t:Double){
 background()
 if t<5.7 {
  let collect=progress(t,3.0,4.0)
  layer(collect){plane(Pose(x:960,y:610)){stock(1520,620,"E7E8EA",0.11)
   text("Editorial",-690,-252,31,ink,"medium");text("Collection",690,-252,25,muted,"sans","right")
   line(-690,-221,690,-221,"CDD0D4")
  }}
  for i in [4,3,1,0,2] {
   let pose=sortedPose(i,min(t,3)).toward(collectionPose(i),collect)
   layer(i==3 || i==4 ? 1-collect:1){specimen(cardNames[i],cardWords[i],cardFaces[i],cardColors[i],pose)}
  }
  if t<3 {title("Explore your library",t+0.34,true,"Sort by name, style count or category.")}
  else {title("Organize by project",t-3,true,"Named collections keep your fonts together.")}
 } else if t<8.2 {
  let p=progress(t,5.7,6.65)
  layer(1-p){plane(Pose(x:960,y:610)){stock(1520,620,"E7E8EA",0.11);text("Editorial",-690,-252,31,ink,"medium");text("Collection",690,-252,25,muted,"sans","right");line(-690,-221,690,-221,"CDD0D4")}}
  layer(1-p){let pose=collectionPose(1);specimen(cardNames[1],cardWords[1],cardFaces[1],cardColors[1],Pose(x:pose.x+p*1000,y:pose.y,s:pose.s))}
  for i in [0,2] {
   let pose=collectionPose(i).toward(shortlistPose(i),p)
   specimen(cardNames[i],"Form",cardFaces[i],paper,pose)
   shortlistMark(pose,progress(t,6.45,6.85))
  }
  title("Build your shortlist",t-5.7,true,"Keep your strongest candidates together.")
 } else {
  let p=progress(t,8.2,9.1),clear=progress(t,10.5,10.9)
  layer(1-p){specimen("Didot","Form","didot",paper,shortlistPose(0).toward(Pose(x:960,y:615),p))}
  let pose=shortlistPose(2).toward(Pose(x:960,y:615),p),w=mix(560,1280,p),h=mix(620,650,p)
  plane(pose){
   stock(w,h,paper)
   let left = -w/2+mix(50,66,p),right=w/2-66
   layer(1-clear){text("Baskerville",left,-h/2+62,28,blue,"medium");layer(p){text("Didot",right,-h/2+62,28,"B05732","medium","right")};line(left,-h/2+98,right,-h/2+98,"C5C8CD")}
   let size=mix(140,228,p),bx = -bounds("Form",size,"serif").width/2,by=mix(74,55,p)
   text("Form",bx,by,size,blendedHex(ink,blue,p*(1-clear)),"serif")
   layer(p*(1-clear)*0.66){save{c.setBlendMode(.multiply);text("Form",bx,by,size,"B05732","didot")}}
   layer(p*(1-clear)){text("Same text. Same size.",0,h/2-52,24,muted,"sans","center")}
  }
  title("Compare every detail",t-8.2,true,"A/B overlays reveal the difference.")
 }
 navigation(t,0)
}
let studyHeads=["serif","didot","medium"]
let studyBodies=["sans","futura","mono"]
let studyHeadNames=["Baskerville","Didot","Helvetica Neue"]
let studyBodyNames=["Helvetica Neue","Futura","Menlo"]
func suggestionRows(_ local:Double){
 layer(progress(local,0.35,0.8)){text("Body suggestions",1390,302,23,muted,"sans","center")}
 for i in 0..<3 {
  let p=progress(local,0.35+Double(i)*0.10,0.80+Double(i)*0.10)
  layer(p){plane(Pose(x:1390,y:395+Double(i)*210+18*(1-p))){
   stock(470,160,paper,0.07)
   text(studyBodyNames[i],-195,-28,28,ink,"medium")
   text("The shape of ideas",-195,25,26,ink,studyBodies[i])
   if i==0 {layer(progress(local,1.45,1.8)){line(-195,57,195,57,blue,2)}}
  }}
 }
}
func studyCard(_ i:Int,_ pose:Pose,_ w:Double=500,_ h:Double=620,_ detail:Double=1,_ layout:Double=0,_ comparison:Bool=true,_ headingSize:Double?=nil,_ alternative:Double=0){
 plane(pose){
  stock(w,h,paper,0.10)
  let size=headingSize ?? min(156,(w-84)*0.25),left = -w/2+42
  // The same content and dimensions make differences in pairing easy to compare.
  let headlineFaces=[("serif",1-alternative),(studyHeads[i],alternative)]
  for (face,opacity) in headlineFaces {layer(opacity){
   let x=mix(0,left+bounds("Form",size,face).width/2,layout)
   text("Form",x,mix(55,-88,detail),size,ink,face,"center")
  }}
  layer(detail){
   text(comparison ? ["A","B","C"][i]:"Baskerville",left,-h/2+48,25,ink,"medium")
   text(comparison ? "Editorial study":"Heading",w/2-42,-h/2+48,22,muted,"sans","right")
   line(left,-h/2+76,w/2-42,-h/2+76,"CDD0D4")
   let subSize=size*0.53
   for (face,opacity) in headlineFaces {layer(opacity){
    text("& feeling",mix(0,left+bounds("& feeling",subSize,face).width/2,layout),-18,subSize,ink,face,"center")
   }}
   for (j,s) in ["An independent journal","on culture and design."].enumerated(){
    text(s,mix(0,left+bounds(s,25,studyBodies[i]).width/2,layout),61+Double(j)*36,25,ink,studyBodies[i],"center")
   }
   rect(mix(-28,left,layout),132,56,4,coral)
   text("Typography journal",mix(0,left+bounds("Typography journal",23,studyBodies[i]).width/2,layout),183,23,ink,studyBodies[i],"center")
   layer(1-alternative){text("Baskerville",left,h/2-62,22,muted,"sans")}
   layer(alternative){text(studyHeadNames[i],left,h/2-62,22,muted,"sans")}
   text(studyBodyNames[i],left,h/2-30,22,muted,"sans")
  }
 }
}
func pairingSuggestions(_ local:Double){
 background()
 let p=progress(local,0,0.9),details=progress(local,0.5,1.1)
 studyCard(0,Pose(x:mix(960,600,p),y:mix(615,620,p)),mix(1280,850,p),mix(650,610,p),details,0,false,mix(228,156,p))
 suggestionRows(local)
 title("Find a font pairing",local,true,"Pairing suggestions from your own library")
 navigation(local,1)
}
func studySurfaces(_ local:Double){
 let p=progress(local,0,0.8)
 layer(1-progress(local,0,0.32)){suggestionRows(4)}
 studyCard(0,Pose(x:mix(600,400,p),y:620),mix(850,500,p),mix(610,620,p),1,0,local>0.25)
 for i in 1...2 {
  let q=progress(local,0.12+Double(i-1)*0.18,0.87+Double(i-1)*0.18)
  if q>0 {layer(q){studyCard(i,Pose(x:mix(2100+Double(i)*280,400+Double(i)*560,q),y:620),500,620,1,i==1 ? progress(local,3.7,4.4):0,true,nil,progress(local,i==1 ? 2.05:2.65,i==1 ? 2.45:3.05))}}
 }
}
func pairingStudies(_ local:Double){
 background();studySurfaces(local)
 title("Try pairings in context",local,true,"Explore layouts side by side in Spaces")
 navigation(local,1)
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
var exportedPNorm=CGAffineTransform(a:1/rawBounds.height,b:0,c:0,d:-1/rawBounds.height,tx:-rawBounds.midX/rawBounds.height,ty:rawBounds.midY/rawBounds.height)
let exportedP=rawP.copy(using:&exportedPNorm)!

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
 transform(x,y,h){c.setFillColor(color(ink));c.addPath(outline(bend));c.fillPath()}
 layer(control){
  let lowY=y+h/2,topY=y-h/2
  line(300,topY,1620,topY,"CDD0D4");line(300,lowY,1620,lowY,"CDD0D4")
  text("x-height",300,topY-15,21,muted);text("Descender",300,lowY+34,21,muted)
  transform(x,y,h){c.setStrokeColor(color(blue));c.setLineWidth(1.6/h);c.addPath(outline(bend));c.strokePath()}
  var last=CGPoint.zero
  func pos(_ p:CGPoint)->CGPoint{let a=altered(p,bend);return CGPoint(x:x+a.x*h,y:y+a.y*h)}
  var anchorIndex=0
  for s in segments {
   if s.points.isEmpty{continue}
   let end=s.points.last!,point=pos(end)
   if s.kind != .closeSubpath {
    rect(point.x-3.5,point.y-3.5,7,7,stage);c.setStrokeColor(color(blue));c.setLineWidth(1.4);c.stroke(CGRect(x:point.x-3.5,y:point.y-3.5,width:7,height:7))
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
func strokePoint(_ points:[CGPoint],_ fraction:Double)->CGPoint {
 let lengths=zip(points,points.dropFirst()).map{hypot($1.x-$0.x,$1.y-$0.y)}
 var remaining=lengths.reduce(0,+)*clamp(fraction)
 for i in 0..<lengths.count {let length=lengths[i];if remaining<=length {let r=remaining/length;return CGPoint(x:mix(points[i].x,points[i+1].x,r),y:mix(points[i].y,points[i+1].y,r))};remaining-=length}
 return points.last!
}
func tablet(_ t:Double,_ offset:Double=0){
 let file=progress(t,19.05,19.65),depart=progress(t,20.6,21.6),travel=depart*2000
 let deviceWidth=mix(920,1400,file),artScale=mix(0.68,1,file)
 let positions=[392.0,807.0,1197.0],paths=[[3,4],[2],[3,4]]
 transform(offset,0){
  transform(travel+960,610){
   if file<1 {layer(1-file){
    let box=CGRect(x:-deviceWidth/2,y:-325,width:deviceWidth,height:650)
    recordPaper(box)
    save{c.setShadow(offset:CGSize(width:8,height:-12),blur:24,color:color("000000",0.12));c.setFillColor(color("36383C"));c.addPath(CGPath(roundedRect:box,cornerWidth:32,cornerHeight:32,transform:nil));c.fillPath()}
    c.setFillColor(color(paper));c.addPath(CGPath(roundedRect:CGRect(x:-deviceWidth/2+22,y:-303,width:deviceWidth-44,height:606),cornerWidth:17,cornerHeight:17,transform:nil));c.fillPath()
    dot(CGPoint(x:-deviceWidth/2+11,y:0),3,"999DA3")
   }}
   layer(file){fileOutline(deviceWidth,650,paper,46);text("Artwork.png",-deviceWidth/2+76,-289,25,muted,"medium")}
  }
  transform(960,610,artScale){transform(-960,-610){
  let starts=[17.05,17.36,17.76,18.24,18.55],durations=[0.23,0.32,0.40,0.23,0.32]
  var tracks:[(start:Double,end:Double,points:[CGPoint])]=[]
  for i in 0..<3 {
   let origin=i==1 ? 132.0:260.0,dx=i==0 ? 0:travel
   transform(positions[i]+dx,320,3.5){c.translateBy(x:-origin,y:-65);c.setStrokeColor(color(ink));c.setLineWidth(13);c.setLineCap(.round);c.setLineJoin(.round)
    for (j,index) in paths[i].enumerated(){
     let ordinal=i==0 ? j:(i==1 ? 2:3+j),start=starts[ordinal],length=durations[ordinal],fraction=clamp((t-start)/length)
     drawStroke(handwriting[index],fraction)
     tracks.append((start,start+length,handwriting[index].map{CGPoint(x:positions[i]+($0.x-origin)*3.5,y:320+($0.y-65)*3.5)}))
    }
   }
  }
  var pencil:CGPoint?=nil
  for (index,track) in tracks.enumerated() {
   if t>=track.start && t<=track.end {pencil=strokePoint(track.points,(t-track.start)/(track.end-track.start))}
   else if index+1<tracks.count && t>track.end && t<tracks[index+1].start {
    let p=progress(t,track.end,tracks[index+1].start),a=track.points.last!,b=tracks[index+1].points.first!
    pencil=CGPoint(x:mix(a.x,b.x,p),y:mix(a.y,b.y,p)-18*sin(p*Double.pi))
   }
  }
  if let tip=pencil {layer(progress(t,17.05,17.11)*(1-progress(t,18.80,18.87))){save{
   c.translateBy(x:tip.x,y:tip.y);c.rotate(by:0.45)
   c.setLineCap(.round);line(0,-18,0,-135,"B8BCC2",16);line(0,-18,0,-135,paper,13);line(0,-4,0,-13,ink,4)
  }}}
  }}
  let scan=progress(t,19.65,20.02)*(1-progress(t,20.65,21.0))
  layer(scan){for i in 0..<3 {
   let dx=i==0 ? 0:travel,x=positions[i]-(i==1 ? 2:10)+dx,y=i==1 ? 324.0:340.0,w=i==1 ? 349.0:350.0,h=i==1 ? 428.0:550.0
   c.setStrokeColor(color(blue));c.setLineWidth(1.4);c.stroke(CGRect(x:x,y:y,width:w,height:h))
   text(i==1 ? "o":"p",x+w/2,y+h+31,26,blue,"sans","center")
  }}
 }
}
func spacesToTablet(_ local:Double){
 background()
 let p=progress(local,0,1.1)
 transform(-2100*p,0){studySurfaces(6.55)}
 tablet(15.8+local,2100*(1-p))
 layer(1-progress(local,0,0.28)){title("Try pairings in context",1,true,"Explore layouts side by side in Spaces");navigation(local,1)}
 if local>0.4 {title("Draw your way",local-0.4,true,"Use an iPad or a connected drawing tablet.")}
}

func drawingScene(_ t:Double){
 background();tablet(t)
 if t<19.05 {title("Draw your way",1,true,"Use an iPad or a connected drawing tablet.")}
 else {title("Import your artwork",t-19.05,true,"Export PNG, then open it in Letterform Editor.")}
 layer(progress(t,19.3,19.7)){navigation(t,2)}
}
func editing(_ t:Double){
 background()
 let enter=progress(t,11.0,11.6),bend=0.045*progress(t,11.55,12.0)*(1-progress(t,12.25,13.45))
 let leave=progress(t,14.05,14.5)
 let startX=392+(smoothBounds.midX-260)*3.5,startY=320+(smoothBounds.midY-65)*3.5
 let finalX=960-bounds("pop",630,"ink").midX+rawBounds.midX*0.63-70,finalY=723-rawBounds.midY*0.63
 let h=mix(mix(smoothBounds.height*3.5,610,enter),rawBounds.height*0.63,leave)
 let x=mix(mix(startX,960,enter),finalX,leave),y=mix(mix(startY,595,enter),finalY,leave)
 let outlineHandoff=progress(t,14.33,14.5)
 layer(1-outlineHandoff){vectorP(x,y,h,bend,progress(t,11.5,11.8)*(1-leave))}
 layer(outlineHandoff){transform(x,y,h){c.setFillColor(color(ink));c.addPath(exportedP);c.fillPath()}}
 if leave>0 {layer(leave){kernWord(960+320*(1-leave),723,630,70,ink,1)}}
 if t<14.05 {title("Make every curve yours",t-11.0,true,"Editable outlines. Precise Bézier control.")}else{title("Down to the space between",t-14.05)}
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
 title("Down to the space between",t-14.05)
 kernWord(960,723,630,a,ink)
 let b=bounds("pop",630,"ink")
 let lx=960-b.width/2-a,rx=960+b.width/2+a
 line(lx-26,333,lx-26,864,"CDD0D4");line(rx+26,333,rx+26,864,"CDD0D4")
 line(lx-70,742,rx+70,742,"CDD0D4")
 text("Spacing and kerning",960,929,28,muted,"sans","center")
 navigation(t,2)
}
func fileOutline(_ w:Double,_ h:Double,_ fill:String,_ fold:Double){
 recordPaper(CGRect(x:-w/2,y:-h/2,width:w,height:h))
 let left = -w/2,right=w/2,top = -h/2,bottom=h/2
 let p=CGMutablePath();p.move(to:CGPoint(x:left,y:top));p.addLine(to:CGPoint(x:right-fold,y:top));p.addLine(to:CGPoint(x:right,y:top+fold));p.addLine(to:CGPoint(x:right,y:bottom));p.addLine(to:CGPoint(x:left,y:bottom));p.closeSubpath()
 save{c.setShadow(offset:CGSize(width:8,height:-12),blur:24,color:color("000000",0.2));c.setFillColor(color(fill));c.addPath(p);c.fillPath()}
 line(right-fold,top,right-fold,top+fold,"BCC0C5",1.5);line(right-fold,top+fold,right,top+fold,"BCC0C5",1.5)
}
func exportAndReturn(_ t:Double){
 background()
 let p=progress(t,16.65,17.25),returning=progress(t,18.35,19.0)
 for i in [0,4,1,3] {
  let base=libraryPose(i,2.5),pose=Pose(x:base.x+Double(i-2)*600*(1-returning),y:base.y-24*(1-returning),s:base.s,yaw:base.yaw,pitch:base.pitch,roll:base.roll)
  if returning>0 {specimen(cardNames[i],cardWords[i],cardFaces[i],cardColors[i],pose)}
 }
 let w=mix(440,560,returning),h=mix(570,620,returning)
 let position=Pose(x:960,y:590,s:1,yaw:0,pitch:0,roll:0)
 plane(position){
  let reveal=progress(t,16.65,16.95)
  if reveal>0 {transform(0,0,reveal){fileOutline(w,h,paper,58*(1-returning))}}
  layer(progress(t,16.95,17.12)){
   text(returning<0.5 ? "TrueType":"Ink",-w/2+46,-h/2+60,28,ink,"medium")
   text(returning<0.5 ? "Ink.ttf":"Regular",-w/2+46,h/2-44,returning<0.5 ? 32:22,returning<0.5 ? ink:muted)
   if returning>0.5 {text("Aa",w/2-46,h/2-44,24,ink,"sans","right");line(-w/2+46,-h/2+93,w/2-46,-h/2+93,"C5C8CD")}
  }
  kernWord(0,mix(133,55,p),mix(630,236,p),0,ink)
  save{c.clip(to:CGRect(x:-w*reveal/2,y:-h*reveal/2,width:w*reveal,height:h*reveal));kernWord(0,mix(133,55,p),mix(630,236,p),0,ink)}
 }
 if t<18.35 {title("Export your font",t-16.65,true,"Save an installable TrueType file.")}else{title("Add it to Library",t-18.35,true,"Export, then add your font folder.")}
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
  stock(w,h,blendedHex(paper,coral,p))
  layer(1-p){
   text("Ink",-w/2+46,-h/2+60,28,ink,"medium")
   text("Regular",-w/2+46,h/2-44,22,muted)
   text("Aa",w/2-46,h/2-44,24,ink,"sans","right")
   line(-w/2+46,-h/2+93,w/2-46,-h/2+93,"C5C8CD")
  }
  layer(progress(t,20.8,21.2)){formLayout(w,h,1,true)}
  text("pop",0,mix(55,115,p),mix(236,580,p),ink,"ink","center")
 }
 title("Your font, in good company",t-20.15)
 navigation(t,t<20.65 ? 0:1)
}
func layoutHandoff(_ local:Double){
 background()
 let p=progress(local,0.25,1.1)
 plane(Pose(x:mix(960,550,p),y:mix(590,620,p),s:mix(1.075,0.50,p))){
  stock(1280,650,coral)
  formLayout(1280,650,1,true)
  text("pop",0,115,580,ink,"ink","center")
  layer(progress(local,0,0.2)*(1-progress(local,1.0,1.3))){
   c.setStrokeColor(color(blue));c.setLineWidth(1.5);c.stroke(CGRect(x:-644,y:-329,width:1288,height:658))
   for x in [-644.0,644.0] {for y in [-329.0,329.0] {rect(x-3,y-3,6,6,blue)}}
  }
 }
 let reveal=progress(local,0.65,1.15)
 layer(reveal){
  line(918,620,mix(918,1000,reveal),620,muted,2)
  if reveal>0.8 {line(987,608,1000,620,muted,2);line(987,632,1000,620,muted,2)}
  plane(Pose(x:1370+40*(1-reveal),y:620,s:mix(0.96,1,reveal))){
   fileOutline(540,600,paper,52)
   text("Layout export",-224,-236,28,ink,"medium")
   line(-224,-206,224,-206,"CDD0D4")
   text("Figma",0,-108,40,ink,"medium","center")
   text("Illustrator",0,-28,40,ink,"medium","center")
   text("InDesign",0,52,40,ink,"medium","center")
   text("Editable text and shapes",0,236,25,muted,"sans","center")
  }
 }
 title("Export your explorations",local)
 layer(progress(local,0.85,1.1)){text("Continue in Figma, Illustrator or InDesign",960,253,28,muted,"sans","center")}
 if local>0.85 {captionTop=280}
 navigation(local,1)
}
struct MoreTile {
 let x:Double,y:Double,w:Double,h:Double
 let kind:String,title:String,subtitle:String,fill:String
 var box:CGRect {CGRect(x:x,y:y,width:w,height:h)}
}
// A six-column grid with four distinct proportions, not a repeated card template.
let moreTiles:[MoreTile]=[
 MoreTile(x:40,y:42,w:600,h:234,kind:"tokens",title:"Export type tokens",subtitle:"CSS, Tailwind and code starters",fill:"EDF2F2"),
 MoreTile(x:660,y:42,w:290,h:234,kind:"similar",title:"Find similar fonts",subtitle:"Explore your local library",fill:"F6F6F3"),
 MoreTile(x:970,y:42,w:290,h:234,kind:"health",title:"Font health",subtitle:"Inspect and repair copies",fill:"F3F4F3"),
 MoreTile(x:1280,y:42,w:600,h:488,kind:"components",title:"Linked components",subtitle:"Edit once, update linked glyphs",fill:"F3E9E2"),
 MoreTile(x:40,y:296,w:290,h:234,kind:"cost",title:"Web-font cost",subtitle:"Check exact WOFF2 sizes",fill:"F5F5F2"),
 MoreTile(x:350,y:296,w:290,h:234,kind:"coverage",title:"Character coverage",subtitle:"Check the text you need",fill:"EEF2F2"),
 MoreTile(x:40,y:550,w:290,h:488,kind:"masters",title:"Alternate masters",subtitle:"Independent designs",fill:"EAF0F0"),
 MoreTile(x:350,y:550,w:600,h:234,kind:"cleanup",title:"Simplify outlines",subtitle:"Preview cleaner curves",fill:"F3F4F2"),
 MoreTile(x:970,y:550,w:600,h:234,kind:"return",title:"Bring layouts back",subtitle:"Editable text and shapes",fill:"EEF1F1"),
 MoreTile(x:1590,y:550,w:290,h:234,kind:"folders",title:"Live folders",subtitle:"Keep local fonts in view",fill:"F5F5F2"),
 MoreTile(x:350,y:804,w:290,h:234,kind:"proof",title:"Type proofing",subtitle:"Contrast and line lengths",fill:"F6F6F3"),
 MoreTile(x:660,y:804,w:290,h:234,kind:"rediscover",title:"Rediscover fonts",subtitle:"Based on your past use",fill:"F0F3F3"),
 MoreTile(x:970,y:804,w:290,h:234,kind:"variable",title:"Variable fonts",subtitle:"Fine-tune supported axes",fill:"F5F1ED"),
 MoreTile(x:1280,y:804,w:290,h:234,kind:"duplicates",title:"Find duplicates",subtitle:"Compare copies and versions",fill:"F5F5F2"),
 MoreTile(x:1590,y:804,w:290,h:234,kind:"activation",title:"Activate fonts",subtitle:"Across apps, for the session",fill:"EEF2F2")
]
func rounded(_ box:CGRect,_ radius:Double,_ fill:String){
 c.setFillColor(color(fill));c.addPath(CGPath(roundedRect:box,cornerWidth:radius,cornerHeight:radius,transform:nil));c.fillPath()
}
func moreGraphic(_ kind:String,_ local:Double){
 let p=progress(local,0.65,1.35)
 switch kind {
 case "tokens":
  text("{",74,160,102,blue,"mono","center")
  text("Aa",192,151,95,ink,"serif","center")
  text("}",324,160,102,blue,"mono","center")
  for (i,w) in [118.0,78,98].enumerated(){rect(160,174+Double(i)*10,w*p,3,i==0 ? coral:"B6C2C3")}
 case "cost":
  for (i,w) in [252.0,188,120].enumerated(){
   let y=66+Double(i)*48
   rounded(CGRect(x:90,y:y,width:260,height:14),7,"E0E5E5")
   rounded(CGRect(x:90,y:y,width:max(14,w*p),height:14),7,i==0 ? blue:(i==1 ? "7D9B9C":coral))
  }
  text("WOFF2",220,205,24,muted,"mono","center")
 case "similar":
  let names=["serif","didot","serif"]
  for i in 0..<3 {layer(i==1 ? 1:0.55){text("Ag",100+Double(i)*120,151,i==1 ? 87:70,ink,names[i],"center")}}
  line(190,187,250,187,blue,2)
 case "health":
  rounded(CGRect(x:137,y:40,width:148,height:164),12,"FFFFFF")
  text("Aa",211,143,78,ink,"serif","center")
  line(165,173,252,173,"CDD0D4",2)
  let points=[CGPoint(x:266,y:181),CGPoint(x:284,y:199),CGPoint(x:320,y:155)]
  c.setLineWidth(5);c.setLineCap(.round);c.setStrokeColor(color(blue));drawStroke(points,p)
 case "components":
  text("A",115,172,136,ink,"serif","center")
  line(192,133,240,133,"9BADAE",2);line(240,81,240,171,"9BADAE",2)
  line(240,81,260,81,"9BADAE",2);line(240,171,260,171,"9BADAE",2)
  layer(p){text("Á",314,113,75,blue,"serif","center");text("Å",314,204,75,blue,"serif","center")}
 case "cleanup":
  for i in 0..<2 {
   let x=i==0 ? 112.0:328.0
   let path=CGPath(ellipseIn:CGRect(x:x-54,y:61,width:108,height:128),transform:nil)
   c.addPath(path);c.setStrokeColor(color(ink));c.setLineWidth(3);c.strokePath()
   let count=i==0 ? 20:4
   for k in 0..<count {
    let angle=Double(k)*2*Double.pi/Double(count),xx=x+54*cos(angle),yy=125+64*sin(angle)
    rect(xx-3,yy-3,6,6,i==0 ? "819697":blue)
   }
  }
  line(191,125,249,125,muted,2);line(238,115,249,125,muted,2);line(238,135,249,125,muted,2)
 case "masters":
  for i in 0..<3 {
   let x=72+Double(i)*105
   rounded(CGRect(x:x,y:42+Double(abs(i-1))*10,width:96,height:154),10,i==1 ? "FFFFFF":"E2E8E8")
   text("a",x+48,151,91,ink,["serif","medium","didot"][i],"center")
  }
 case "proof":
  rounded(CGRect(x:66,y:44,width:148,height:127),14,ink)
  rounded(CGRect(x:226,y:44,width:148,height:127),14,"E4EBEB")
  text("Aa",140,134,78,"FFFFFF","serif","center")
  text("Aa",300,134,78,blue,"serif","center")
  line(70,197,370,197,"9AADAE",2)
  for x in stride(from:70.0,through:370.0,by:30){line(x,192,x,202,"9AADAE",1)}
 case "return":
  for (i,name) in ["Figma","Adobe"].enumerated(){
   let x=58+Double(i)*181
   rounded(CGRect(x:x,y:39,width:143,height:105),12,"E4EBEB")
   text("Aa",x+71.5,110,68,ink,"serif","center")
   text(name,x+71.5,174,23,muted,"sans","center")
  }
  line(130,190,130,209,blue,1.5);line(130,209,310,209,blue,1.5);line(310,190,310,209,blue,1.5)
  line(220,209,220,226,blue,1.5);line(213,219,220,226,blue,1.5);line(227,219,220,226,blue,1.5)
 case "rediscover":
  text("Ag",220,159,108,ink,"serif","center")
  let start=0.45,end=5.50
  c.beginPath();c.addArc(center:CGPoint(x:220,y:127),radius:88,startAngle:start,endAngle:mix(start,end,p),clockwise:false)
  c.setStrokeColor(color("8DA6A7"));c.setLineWidth(2);c.strokePath()
  if p>0.95 {line(273,50,282,65,"8DA6A7",2);line(282,65,265,66,"8DA6A7",2)}
 default:break
 }
}
func raisedSheet(_ box:CGRect,_ radius:Double=12,_ fill:String="FFFFFF") {
 save{c.setShadow(offset:CGSize(width:0,height:-5),blur:15,color:color("253638",0.10));rounded(box,radius,fill)}
}
func compactGraphic(_ kind:String,_ local:Double){
 let p=progress(local,0.65,1.35)
 switch kind {
 case "coverage":
  for (i,s) in ["Å","é","ß"].enumerated(){
   let x=41+Double(i)*76
   rounded(CGRect(x:x,y:32,width:57,height:70),9,"FFFFFF")
   text(s,x+28.5,87,48,ink,"serif","center")
   line(x+20,121,x+27,128,blue,2);line(x+27,128,x+39,114,blue,2)
  }
 case "folders":
  rounded(CGRect(x:75,y:40,width:59,height:28),7,"B9CBCD")
  rounded(CGRect(x:75,y:55,width:140,height:82),10,"CBDADC")
  raisedSheet(CGRect(x:116,y:37,width:67,height:83),6)
  text("Aa",149.5,94,40,ink,"serif","center")
  rounded(CGRect(x:75,y:76,width:140,height:64),10,"B7CDD0")
  line(178,102,178,124,"FFFFFF",2);line(167,113,189,113,"FFFFFF",2)
 case "variable":
  text("Aa",98,109,89,ink,"medium","center")
  for i in 0..<2 {
   let y=63+Double(i)*46,x=190.0
   line(x,y,x+60,y,"C1B7AF",3)
   dot(CGPoint(x:x+mix(16,Double(i==0 ? 48:27),p),y:y),6,blue)
  }
 case "duplicates":
  for i in 0..<2 {
   let x=71+Double(i)*65,y=32+Double(i)*13
   raisedSheet(CGRect(x:x,y:y,width:81,height:99),8)
   text("Aa",x+40.5,y+64,48,ink,"serif","center")
   line(x+19,y+82,x+62,y+82,"CCD3D3",1.5)
  }
 case "activation":
  for i in 0..<3 {
   let x=59+Double(i)*67
   rounded(CGRect(x:x,y:91,width:39,height:39),8,i==1 ? "C9DBDD":"DEE6E6")
   line(x+19.5,91,x+19.5,74,"9EB6B8",1.5)
  }
  line(78.5,74,212.5,74,"9EB6B8",1.5)
  raisedSheet(CGRect(x:116,y:20,width:59,height:65),7)
  text("Aa",145.5,65,37,ink,"serif","center")
 default:
  // Compact supporting tiles retain a generous text zone below their illustration.
  transform(20,5,250/440){moreGraphic(kind,local)}
 }
}
func moreMosaic(_ local:Double){
 let p=progress(local,0.65,1.35)
 for tile in moreTiles {
  transform(tile.x,tile.y){
   save{c.setShadow(offset:CGSize(width:0,height:-3),blur:10,color:color("253638",0.045));rounded(CGRect(x:0,y:0,width:tile.w,height:tile.h),24,tile.fill)}
   switch tile.kind {
   case "components":
    text(tile.title,34,58,36,ink,"medium")
    text(tile.subtitle,34,96,24,muted)
    // A source letter and two floating, linked accents make this the hero tile.
    raisedSheet(CGRect(x:37,y:159,width:221,height:268),16)
    text("A",147.5,361,211,ink,"serif","center")
    line(258,294,304,294,"ACB7B3",2)
    line(304,225,304,365,"ACB7B3",2)
    line(304,225,335,225,"ACB7B3",2);line(304,365,335,365,"ACB7B3",2)
    for (i,glyph) in ["Á","Å"].enumerated(){
     let y=156+Double(i)*157,dy=10*(1-p)
     raisedSheet(CGRect(x:335,y:y+dy,width:216,height:137),12)
     text(glyph,443,y+109+dy,109,blue,"serif","center")
    }
   case "tokens":
    text("Export",32,70,32,ink,"medium")
    text("type tokens",32,108,32,ink,"medium")
    text("CSS, Tailwind",32,156,22,muted)
    text("and code starters",32,185,22,muted)
    raisedSheet(CGRect(x:294,y:27,width:279,height:181),13)
    text("Aa",325,88,52,blue,"serif")
    text("--font-heading",325,123,18,ink,"mono")
    text("--font-body",325,152,18,ink,"mono")
    line(325,180,325+113*p,180,coral,3)
   case "masters":
    text(tile.title,145,49,27,ink,"medium","center")
    text(tile.subtitle,145,81,20,muted,"sans","center")
    for i in 0..<3 {
     let y=116+Double(i)*98,x=39+Double(i)*15
     save{c.translateBy(x:x+91,y:y+72);c.rotate(by:Double(i-1)*0.045)
      raisedSheet(CGRect(x:-91,y:-72,width:182,height:144),12,i==1 ? "F7F7F4":"FFFFFF")
      text("a",0,44,122,ink,["serif","medium","didot"][i],"center")
     }
    }
   case "cleanup":
    text(tile.title,28,61,30,ink,"medium")
    text("Preview cleaner curves",28,99,22,muted)
    transform(293,26,0.66){moreGraphic(tile.kind,local)}
   case "return":
    text(tile.title,28,61,30,ink,"medium")
    text("Import editable",28,99,22,muted)
    text("text and shapes",28,128,22,muted)
    transform(301,32,0.62){moreGraphic(tile.kind,local)}
   default:
    compactGraphic(tile.kind,local)
    text(tile.title,145,182,27,ink,"medium","center")
    text(tile.subtitle,145,214,19,muted,"sans","center")
   }
  }
 }
 // The open center provides hierarchy and breathing room within the dense wall.
 text("And more",960,435,90,ink,"medium","center")
}
func moreFeatures(_ local:Double){
 background()
 let slide=progress(local,0,0.65)
 if slide<1 {transform(-1920*slide,0){layoutHandoff(3.85)}}
 transform(1920*(1-slide),0){moreMosaic(local)}
 // This is a full-screen overview without scene captions or workspace navigation.
 captionTop=0;navVisible=false
}
func ending(_ t:Double){
 background()
 let p=progress(t,36,36.58)
 layer(p){transform(0,16*(1-p)){
  // Center each visible line on the wordmark axis; verify the rendered lockup too.
  let center=Double(width)/2
  image(icon,CGRect(x:center-100,y:282,width:200,height:200))
  text("Typefield",center,620,112,ink,"medium","center")
  text("Quite the character",center,692,36,muted,"sans","center")
  text("For Mac",center,759,24,muted,"sans","center")
 }}
}
// Revision 8 scene seconds mapped to the approved editor/export choreography.
let timing:[(story:Double,output:Double)]=[
 (4,12.3),(5.3,13.2),(6.45,14.35),(7.65,15.8),
 (11,21.6),(11.6,22.3),(12.25,22.95),(13.45,24.30),(14.05,24.95),(14.5,25.45),
 (14.65,25.65),(15.65,26.7),(16.65,27.95),(16.95,28.35),(17.12,28.52),
 (17.25,28.65),(18.35,30),(19,30.75),(20.15,32.2),(21.15,33.35),
 (21.2,33.4),(22.4,34.6),(23.3,35.35),(24,36)
]
func storyTime(_ outputTime:Double)->Double {
 for (a,b) in zip(timing,timing.dropFirst()) where outputTime<=b.output {
  return mix(a.story,b.story,clamp((outputTime-a.output)/(b.output-a.output)))
 }
 return timing.last!.story
}
// Preserve readable action timing while giving pairing exploration the central beat.
// The export leads into a feature mosaic, followed by the four-second closing card.
let pacing:[(scene:Double,output:Double)]=[
 (0,0),(2,2),(3,3.3),(4,4.3),(5.7,6.3),(6.85,7.45),
 (8.2,9.15),(9.1,10.05),(10.5,11.95),(11,12.45),(12.3,16.45),
 (15.8,23),(16.9,24.1),(17.05,24.25),(18.87,26.35),(19.05,27),
 (19.65,27.6),(20.02,27.97),(20.6,28.8),(21.6,29.8),
 (22.3,30.5),(22.7,30.9),(22.95,31.25),(24.3,32.6),(24.95,33.2),(25.45,33.7),
 (25.65,33.9),(26.7,34.95),(27.95,36.2),(28.65,36.9),(30,38.1),
 (30.75,38.85),(32.2,40.35),(33.4,41.55),(34.6,42.75),(35.35,43.5),
 (36,44.15),(39.85,48),(46.35,55.5),(50.35,59.5)
]
func choreographyTime(_ outputTime:Double)->Double {
 for (a,b) in zip(pacing,pacing.dropFirst()) where outputTime<=b.output {
  return mix(a.scene,b.scene,clamp((outputTime-a.output)/(b.output-a.output)))
 }
 return pacing.last!.scene
}
func presentationTime(_ sceneTime:Double)->Double {
 for (a,b) in zip(pacing,pacing.dropFirst()) where sceneTime<=b.scene {
  return mix(a.output,b.output,clamp((sceneTime-a.scene)/(b.scene-a.scene)))
 }
 return pacing.last!.output
}
func frame(_ outputTime:Double)->CGContext {
 let sceneTime=choreographyTime(outputTime),t=storyTime(sceneTime)
 let ctx=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:rgb,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 c=ctx;c.translateBy(x:0,y:1080);c.scaleBy(x:1,y:-1);c.setAllowsAntialiasing(true);c.setShouldAntialias(true);c.interpolationQuality = .high
 paperBounds=[];navVisible=false;captionTop=230
 if sceneTime<11 {libraryStory(sceneTime)}
 else if sceneTime<12.3 {pairingSuggestions(outputTime-12.45)}
 else if sceneTime<15.8 {pairingStudies(outputTime-16.45)}
 else if sceneTime<16.9 {spacesToTablet(outputTime-23)}
 else if sceneTime<21.6 {drawingScene(sceneTime)}
 else if sceneTime<25.45 {editing(t)}
 else if sceneTime<27.95 {spacing(t)}
 else if sceneTime<32.2 {exportAndReturn(t)}
 else if sceneTime<36 {finalLayout(t)}
 else if sceneTime<39.85 {layoutHandoff(outputTime-44.15)}
 else if sceneTime<46.35 {moreFeatures(outputTime-48)}
 else {ending(36+outputTime-55.5)}
 validateGeometry(outputTime)
 return ctx
}
func png(_ ctx:CGContext,_ url:URL)throws {try NSBitmapImageRep(cgImage:ctx.makeImage()!).representation(using:.png,properties:[:])!.write(to:url)}
if let k=args.firstIndex(of:"--frame"),args.count>k+1 {let t=Double(args[k+1])!;try png(frame(t),output.appendingPathComponent(String(format:"v16-%05.2f.png",t)))}
else if args.contains("--stills"){
 for scene in [0.0,1.4,2.6,3.5,4.8,5.9,6.8,7.8,8.6,9.5,10.7,11.7,12.5,14.6,15.9,16.3,16.8,17.5,18.6,19.4,20.2,20.8,21.59,21.61,22.6,24.1,25.35,25.5,26.9,28.2,29.3,30.4,31.5,32.19,32.21,33.5,35.4,36.3,37.2,39.5,40.15,40.65,41.35,43.05,45.35,46.349,46.35,47.55,49.85]{let t=presentationTime(scene);try png(frame(t),output.appendingPathComponent(String(format:"v16-%05.2f.png",t)))}
 print("Rendered 49 composition and transition frames.")
}else if args.contains("--audit"){
 let resolvedHeadingFont=CTFontCopyPostScriptName(font(88,"medium")) as String
 precondition(resolvedHeadingFont=="HelveticaNeue-Medium")
 print("Heading font: \(resolvedHeadingFont)")
 let headings=["Explore your library","Organize by project","Build your shortlist","Compare every detail","Find a font pairing","Try pairings in context","Draw your way","Import your artwork","Make every curve yours","Down to the space between","Export your font","Add it to Library","Your font, in good company","Export your explorations","And more"]
 for h in headings {precondition(bounds(h,88,"medium").width<1760);print("Heading: \(h), \(Int(bounds(h,88,"medium").width)) px")}
 for (i,tile) in moreTiles.enumerated() {
  if tile.w==290 {
   precondition(bounds(tile.title,27,"medium").width<tile.w-40)
   precondition(bounds(tile.subtitle,tile.kind=="masters" ? 20:19).width<tile.w-28)
  }
  precondition(tile.x>=40 && tile.y>=32 && tile.x+tile.w<=1880 && tile.y+tile.h<=1048)
  for other in moreTiles.dropFirst(i+1) {precondition(!tile.box.insetBy(dx:-9,dy:-9).intersects(other.box.insetBy(dx:-9,dy:-9)))}
 }
 precondition(moreTiles.count==15)
 precondition(bounds("Linked components",36,"medium").width<532)
 precondition(bounds("Edit once, update linked glyphs",24).width<532)
 for label in ["Simplify outlines","Bring layouts back"] {precondition(bounds(label,30,"medium").width<270)}
 precondition(bounds("Preview cleaner curves",22).width<270)
 for label in ["and code starters","Import editable","text and shapes"] {precondition(bounds(label,22).width<248)}
 precondition(navCenters[1]==960 && navCenters[1]-navCenters[0]==navCenters[2]-navCenters[1])
 var letters=Array("pop".utf16),gs=[CGGlyph](repeating:0,count:3)
 precondition(CTFontGetGlyphsForCharacters(font(100,"ink"),&letters,&gs,3) && gs.allSatisfy{$0>0})
 for (a,b) in zip(timing,timing.dropFirst()) {precondition(b.story>a.story && b.output>a.output)}
 for (a,b) in zip(pacing,pacing.dropFirst()) {precondition(b.scene>a.scene && b.output>a.output)}
 precondition(pacing.last!.output==duration)
 for t in stride(from:0.0,to:duration,by:0.2) {
  precondition(abs(presentationTime(choreographyTime(t))-t)<0.000001)
  autoreleasepool{_ = frame(t)}
 }
 for knot in pacing {for delta in [-0.001,0.0,0.001] {autoreleasepool{_ = frame(clamp((knot.output+delta)/duration)*duration)}}}
 for t in [10.999,11,12.299,12.3,15.799,15.8,16.899,16.9,21.599,21.6,25.449,25.45,27.949,27.95,32.199,32.2,35.999,36,39.999] {autoreleasepool{_ = frame(presentationTime(t))}}
 print("Verified heading bounds, equal workspace columns, actual exported glyphs, monotonic pacing and round-trip timing, and sampled composition clearance. Every rendered master frame also enforces clearance.")

}else{
 let proc=Process();proc.executableURL=URL(fileURLWithPath:"/opt/homebrew/bin/ffmpeg")
 proc.arguments=["-hide_banner","-loglevel","error","-y","-f","rawvideo","-pixel_format","rgba","-video_size","1920x1080","-framerate","60","-i","pipe:0","-an","-vf","scale=in_range=full:out_range=tv:out_color_matrix=bt709,format=yuv420p","-c:v","libx264","-preset","medium","-crf","16","-color_primaries","bt709","-color_trc","bt709","-colorspace","bt709","-movflags","+faststart",output.appendingPathComponent("Typefield-Launch-Master-1080p60-v16.mp4").path]
 let pipe=Pipe();proc.standardInput=pipe;try proc.run()
 for i in 0..<Int(duration*Double(fps)){try autoreleasepool{let ctx=frame(Double(i)/Double(fps));try pipe.fileHandleForWriting.write(contentsOf:Data(bytesNoCopy:ctx.data!,count:width*height*4,deallocator:.none))};if i%(fps*4)==0{print("Rendered \(i/fps)s / \(duration)s");fflush(stdout)}}
 try pipe.fileHandleForWriting.close();proc.waitUntilExit();precondition(proc.terminationStatus==0);print("Master complete.")
}
