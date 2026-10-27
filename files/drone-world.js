'use strict';
/* Local, dependency-free WebGL scene. Real perspective, depth testing and lighting;
   the campaign's canvas composites this feed with its instrument overlay. */
const DroneWorld={canvas:null,gl:null,meshes:{},lost:false};
const dv={add:(a,b)=>a.map((v,i)=>v+b[i]),sub:(a,b)=>a.map((v,i)=>v-b[i]),dot:(a,b)=>a.reduce((s,v,i)=>s+v*b[i],0),cross:(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]],unit:a=>{const n=Math.hypot(...a)||1;return a.map(v=>v/n)}};
function droneFloor(x,z){return -.9+Math.sin(x*.13)*.45+Math.cos(z*.17)*.35+Math.sin((x+z)*.09)*.4}
function droneForward(e){return [Math.sin(e.yaw)*Math.cos(e.pitch),Math.sin(e.pitch),-Math.cos(e.yaw)*Math.cos(e.pitch)]}
function droneDistance(a,b){return Math.hypot(a.x-b.x,a.y-b.y,a.z-b.z)}
function droneView(eye,at){const z=dv.unit(dv.sub(eye,at)),x=dv.unit(dv.cross([0,1,0],z)),y=dv.cross(z,x);return new Float32Array([x[0],y[0],z[0],0,x[1],y[1],z[1],0,x[2],y[2],z[2],0,-dv.dot(x,eye),-dv.dot(y,eye),-dv.dot(z,eye),1])}
function dronePerspective(aspect){const f=1/Math.tan(Math.PI/5.5),n=.1,far=180;return new Float32Array([f/aspect,0,0,0,0,f,0,0,0,0,(far+n)/(n-far),-1,0,0,2*far*n/(n-far),0])}
function droneModel(x,y,z,sx,sy,sz,yaw=0){const co=Math.cos(yaw),si=Math.sin(yaw);return new Float32Array([co*sx,0,-si*sx,0,0,sy,0,0,si*sz,0,co*sz,0,x,y,z,1])}
function droneMesh(vertices){const gl=DroneWorld.gl,b=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,b);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(vertices),gl.STATIC_DRAW);return {buffer:b,count:vertices.length/6}}
function droneTriangle(v,a,b,d){const n=dv.unit(dv.cross(dv.sub(b,a),dv.sub(d,a)));for(const p of [a,b,d])v.push(...p,...n)}
function droneInit(){
 if(DroneWorld.gl)return !DroneWorld.lost;
 const cv=document.createElement('canvas'),gl=cv.getContext('webgl',{alpha:false,antialias:true,preserveDrawingBuffer:false});if(!gl)return false;
 DroneWorld.canvas=cv;DroneWorld.gl=gl;
 cv.addEventListener('webglcontextlost',ev=>{ev.preventDefault();DroneWorld.lost=true;if(cr&&cr.expedition&&state==='playing')pause()});
 cv.addEventListener('webglcontextrestored',()=>{DroneWorld.gl=null;DroneWorld.lost=false;droneInit()});
 const shader=(type,src)=>{const s=gl.createShader(type);gl.shaderSource(s,src);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw Error(gl.getShaderInfoLog(s));return s};
 const vert=shader(gl.VERTEX_SHADER,`attribute vec3 aPosition;attribute vec3 aNormal;uniform mat4 uModel,uView,uProjection;varying vec3 vWorld,vNormal;void main(){vec4 p=uModel*vec4(aPosition,1.);vWorld=p.xyz;vNormal=normalize(mat3(uModel)*aNormal);gl_Position=uProjection*uView*p;}`);
 const frag=shader(gl.FRAGMENT_SHADER,`precision mediump float;varying vec3 vWorld,vNormal;uniform vec3 uEye,uForward,uColor;uniform float uGlow,uTime,uScan;void main(){vec3 delta=vWorld-uEye;float dist=length(delta);float cone=smoothstep(.72,.98,dot(normalize(delta),uForward));float lamp=cone*2.4/(1.+dist*dist*.007);float diffuse=.55+.45*max(dot(normalize(vNormal),normalize(vec3(-.4,1.,.3))),0.);float caustic=sin(vWorld.x*.65+uTime*.6+sin(vWorld.z*.4))*sin(vWorld.z*.8-uTime*.4);vec3 col=uColor*(diffuse+lamp+uGlow+max(caustic,0.)*.09);float sonar=(1.-smoothstep(0.,1.5,abs(dist-uScan)))*step(.01,uScan);col+=vec3(.15,.65,.48)*sonar;float fog=1.-exp(-dist*.016);col=mix(col,vec3(.035,.16,.19),fog);col=col/(vec3(1.)+col*.35);col=pow(max(col,vec3(0.)),vec3(.78));gl_FragColor=vec4(col,1.);}`);
 const p=gl.createProgram();gl.attachShader(p,vert);gl.attachShader(p,frag);gl.linkProgram(p);if(!gl.getProgramParameter(p,gl.LINK_STATUS))throw Error(gl.getProgramInfoLog(p));gl.deleteShader(vert);gl.deleteShader(frag);DroneWorld.program=p;
 DroneWorld.uniform={};for(const name of ['Model','View','Projection','Eye','Forward','Color','Glow','Time','Scan'])DroneWorld.uniform[name]=gl.getUniformLocation(p,'u'+name);
 DroneWorld.position=gl.getAttribLocation(p,'aPosition');DroneWorld.normal=gl.getAttribLocation(p,'aNormal');
 const box=[];for(const [a,b,d,e] of [[[-1,-1,1],[1,-1,1],[1,1,1],[-1,1,1]],[[1,-1,-1],[-1,-1,-1],[-1,1,-1],[1,1,-1]],[[-1,-1,-1],[-1,-1,1],[-1,1,1],[-1,1,-1]],[[1,-1,1],[1,-1,-1],[1,1,-1],[1,1,1]],[[-1,1,1],[1,1,1],[1,1,-1],[-1,1,-1]],[[-1,-1,-1],[1,-1,-1],[1,-1,1],[-1,-1,1]]]){droneTriangle(box,a,b,d);droneTriangle(box,a,d,e)}
 const ball=[];for(let j=0;j<8;j++)for(let i=0;i<14;i++){const point=(a,b)=>[Math.sin(a)*Math.cos(b),Math.cos(a),Math.sin(a)*Math.sin(b)],a=j*Math.PI/8,b=i*TAU/14,da=Math.PI/8,db=TAU/14;droneTriangle(ball,point(a,b),point(a+da,b),point(a+da,b+db));droneTriangle(ball,point(a,b),point(a+da,b+db),point(a,b+db))}
 const floor=[];for(let x=-70;x<70;x+=3)for(let z=-70;z<70;z+=3){const a=[x,droneFloor(x,z),z],b=[x,droneFloor(x,z+3),z+3],d=[x+3,droneFloor(x+3,z+3),z+3],e=[x+3,droneFloor(x+3,z),z];droneTriangle(floor,a,b,d);droneTriangle(floor,a,d,e)}
 DroneWorld.meshes={box:droneMesh(box),ball:droneMesh(ball),floor:droneMesh(floor)};return true;
}
function droneObject(mesh,pos,scale,color,glow=0,yaw=0){
 const D=DroneWorld,gl=D.gl,u=D.uniform,m=D.meshes[mesh];gl.bindBuffer(gl.ARRAY_BUFFER,m.buffer);gl.vertexAttribPointer(D.position,3,gl.FLOAT,false,24,0);gl.vertexAttribPointer(D.normal,3,gl.FLOAT,false,24,12);
 gl.uniformMatrix4fv(u.Model,false,droneModel(...pos,...scale,yaw));gl.uniform3fv(u.Color,color);gl.uniform1f(u.Glow,glow);gl.drawArrays(gl.TRIANGLES,0,m.count);
}
function droneCamera(e){
 const p=[e.x,e.y,e.z],f=droneForward(e);
 if(e.phase==='launch'){const u=smooth(0,1,e.phaseTime/3.2),eye=[mix(8,e.x,u),mix(18,e.y,u),mix(32,e.z,u)],at=dv.add(p,f.map(v=>mix(0,8,u)*v));return {eye,at,f:dv.unit(dv.sub(at,eye))}}
 if(e.phase==='dock'){const u=clamp(e.phaseTime/1.6,0,1),eye=[8,17,30],at=[mix(e.x,e.dock.x,u),mix(e.y,e.dock.y,u),mix(e.z,e.dock.z,u)];return {eye,at,f:dv.unit(dv.sub(at,eye))}}
 return {eye:p,at:dv.add(p,f),f};
}
function droneRender(e,width,height){
 if(!droneInit())return false;
 const D=DroneWorld,gl=D.gl,cv=D.canvas,k=dpr,cw=Math.round(width*k),ch=Math.round(height*k);if(cv.width!==cw||cv.height!==ch){cv.width=cw;cv.height=ch}
 gl.viewport(0,0,cw,ch);gl.enable(gl.DEPTH_TEST);gl.clearColor(.018,.085,.105,1);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);gl.useProgram(D.program);gl.enableVertexAttribArray(D.position);gl.enableVertexAttribArray(D.normal);
 const camera=droneCamera(e),u=D.uniform;D.camera=camera;gl.uniformMatrix4fv(u.View,false,droneView(camera.eye,camera.at));gl.uniformMatrix4fv(u.Projection,false,dronePerspective(width/height));gl.uniform3fv(u.Eye,camera.eye);gl.uniform3fv(u.Forward,camera.f);gl.uniform1f(u.Time,reduced?0:e.clock);gl.uniform1f(u.Scan,e.clock-e.pulse<4?(e.clock-e.pulse)*22:0);
 droneObject('floor',[0,0,0],[1,1,1],[.12,.25,.25]);
 for(const r of e.rocks)droneObject('ball',[r.x,r.y,r.z],[r.r,r.r*.8,r.r],[.11,.23,.25]);
 // Torn cargo hull: a deck and solid ribs, with a clear approach to its payload.
 for(const b of e.structure)droneObject('box',[b.x,b.y,b.z],[b.sx,b.sy,b.sz],b.color||[.15,.25,.25],0,b.yaw||0);
 for(let i=0;i<7;i++){const z=-30+i*2.6;droneObject('box',[-10,2,z],[.15,2,.16],[.3,.39,.35]);droneObject('box',[0,2,z],[.15,2,.16],[.3,.39,.35]);droneObject('box',[-5,.6,z],[5,.1,.1],[.3,.39,.35])}
 // Corroded plating, inspection stripes and rubble make depth and scale readable.
 for(let i=0;i<4;i++){droneObject('box',[-10.13,1.5,-28+i*4],[.08,.22,1.3],[.48,.3,.13]);droneObject('box',[1.43,1,-28+i*4],[.06,.12,1],[.32,.45,.41])}
 for(let i=0;i<45;i++){const x=-35+hash(i+120)*70,z=-45+hash(i+160)*80,r=.15+hash(i+200)*.4;droneObject('ball',[x,droneFloor(x,z)+.05,z],[r,.16,r*1.4],[.2,.32,.29])}
 // The recovery cradle hangs beneath the mothership; its lit mouth faces the site.
 droneObject('ball',[0,24,27],[12,3.2,4],[.12,.21,.24]);droneObject('box',[0,27,27],[3,1.8,1.6],[.11,.2,.22]);
 for(const x of [-2.6,2.6]){droneObject('box',[x,14,24],[.12,2.3,.12],[.24,.75,.59],.8);droneObject('box',[x,19,24],[.035,2.8,.035],[.3,.38,.37])}
 for(const y of [11.7,16.3])droneObject('box',[0,y,24],[2.7,.12,.12],[.24,.75,.59],.8);
 for(const v of e.vents){const phase=(e.clock+v.phase)%6,hot=phase>3.3&&phase<5.2,warn=phase>2.3&&phase<=3.3;droneObject('ball',[v.x,0,v.z],[1.3,.6,1.3],[.12,.17,.18]);for(let j=0;j<(hot?12:4);j++){const age=(e.clock*.5+j/12)%1;droneObject('ball',[v.x+Math.sin(j*3)*age,age*(hot?8:2),v.z+Math.cos(j)*age],[.18+age*.3,.25,.18+age*.3],hot?[.55,.28,.1]:warn?[.4,.35,.12]:[.18,.3,.3],hot?.4:0)}}
 for(const m of e.mines){droneObject('ball',[m.x,m.y,m.z],[m.r,m.r,m.r],[.19,.15,.15]);for(let i=0;i<3;i++){const s=[.12,.12,.12];s[i]=m.r*1.5;droneObject('box',[m.x,m.y,m.z],s,[.38,.24,.18])}droneObject('ball',[m.x,m.y,m.z+m.r],[.16,.16,.12],[1,.18,.08],1)}
 for(const n of e.nodes){droneObject('box',[n.x,n.y,n.z],[.6,.9,.5],[.2,.32,.32]);droneObject('ball',[n.x,n.y+1.1,n.z],[.2,.2,.2],n.done?[.3,1,.65]:[1,.6,.15],1)}
 for(const q of e.items)if(!q.taken)droneObject('box',[q.x,q.y,q.z],[.45,.35,.5],[.65,.45,.18],.15);
 if(!e.cargo){const p=e.target,col=e.kind==='core'?[1,.52,.18]:e.kind==='disarm'&&!e.toolWindow?[.95,.2,.12]:[.3,.85,.65];droneObject('box',[p.x,p.y,p.z],[.9,.65,.7],[.15,.22,.25]);for(const x of [-.6,0,.6])droneObject('box',[p.x+x,p.y+.7,p.z],[.1,.07,.55],col,1)}
 for(let i=0;i<90;i++){const x=-45+hash(i+e.seed)*90,y=1+hash(i+44)*26,z=-50+((hash(i+99)*100+e.clock*.18)%100);droneObject('ball',[x,y,z],[.025,.025,.025],[.4,.65,.62],.35)}
 if(e.phase==='dock'||e.phase==='launch'&&e.phaseTime<2.35){
  const y=e.phase==='launch'?mix(17,14,smooth(0,2,e.phaseTime)):mix(e.y,16,smooth(0,1.6,e.phaseTime));
  droneObject('box',[e.x,y,e.z],[.58,.25,.75],[.5,.31,.08]);
  for(const x of [-.65,.65]){droneObject('box',[e.x+x,y+.33,e.z],[.08,.08,.9],[.55,.38,.12]);droneObject('box',[e.x+x,y-.33,e.z],[.08,.08,.9],[.3,.35,.34])}
  for(const x of [-.85,.85]){droneObject('ball',[e.x+x,y,e.z],[.25,.25,.5],[.07,.12,.15]);droneObject('box',[e.x+x,y,e.z-.48],[.18,.035,.03],[.4,.5,.5])}
  droneObject('ball',[e.x,y,e.z-.8],[.22,.22,.12],[.04,.08,.12]);droneObject('ball',[e.x,y,e.z-.91],[.1,.1,.03],[.23,.65,.68],.35);
  for(const x of [-.4,.4])droneObject('box',[e.x+x,y,e.z-.8],[.1,.07,.05],[.45,.75,.65],.4);
 }
 return true;
}
function droneProject(p,width,height){const cam=DroneWorld.camera;if(!cam)return null;const forward=cam.f,right=dv.unit(dv.cross(forward,[0,1,0])),up=dv.cross(right,forward),d=dv.sub([p.x,p.y,p.z],cam.eye),z=dv.dot(d,forward),f=height/(2*Math.tan(Math.PI/5.5));return {x:width/2+dv.dot(d,right)*f/Math.max(.1,z),y:height/2-dv.dot(d,up)*f/Math.max(.1,z),behind:z<.1}}
