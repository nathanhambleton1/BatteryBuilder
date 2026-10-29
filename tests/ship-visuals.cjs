// Render the real menu, side and projected meshes without a browser/GPU.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),{createCanvas}=require('@napi-rs/canvas');
const read=n=>fs.readFileSync(require('node:path').join(__dirname,'../files',n),'utf8');
const out=createCanvas(1050,9*150),ctx=out.getContext('2d');
const world=vm.createContext({console,ctx,createCanvas,assert});
const core=read('core.js');
vm.runInContext(`
const TAU=Math.PI*2,clamp=(n,a,b)=>Math.max(a,Math.min(b,n)),mix=(a,b,t)=>a+(b-a)*t;
let c=ctx,ambient=.2,night=0,state='playing',surfaced=false,t=0,invulnUntil=0;
const active=()=>false,scale=1.5,dpr=1,shakeX=0,shakeY=0,sub={x:0,y:0};
let cyw=1,syw=0,cpt=1,spt=0,S;
const proj=()=>[860,100];
`+core.slice(core.indexOf('const PALS='),core.indexOf('const SUB_BY_ID='))+
read('render.js').slice(0,read('render.js').indexOf('function drawSky(){'))+
read('combat-upgrades.js').slice(read('combat-upgrades.js').indexOf('function drawTurtleModel'))+
read('render.js').slice(read('render.js').indexOf('/* Shared model-space'),read('render.js').indexOf('function drawSurfaceFx')),world);
vm.runInContext(`
const hashes=new Set();
for(let i=0;i<SUBS.length;i++){
 const m=SUBS[i];S=m;
 c.setTransform(1,0,0,1,0,0);c.fillStyle='#163540';c.fillRect(0,i*150,1050,150);c.fillStyle='#d9e5df';c.font='16px sans-serif';c.fillText(m.name,12,i*150+24);
 const preview=createCanvas(300,110);drawPreview(preview,m,300,110);c.drawImage(preview,120,i*150+24);
 const pixels=preview.getContext('2d').getImageData(0,0,300,110).data;for(let x=0;x<300;x++){assert.equal(pixels[x*4+3],0,m.id+' preview clips top');assert.equal(pixels[((109*300+x)*4)+3],0,m.id+' preview clips bottom')}
 const mesh=buildMesh(m);assert(mesh.faces.length>100);for(const f of mesh.faces)for(const v of f.v)assert(v.every(Number.isFinite),m.id+' invalid vertex');
 hashes.add(JSON.stringify(mesh.faces));
 // Render an actual side-view gameplay model (lamp on).
 const side=createCanvas(300,150),saved=c;c=side.getContext('2d');c.translate(150,95);c.scale(1.7,1.7);drawSubModel(m,true);assert.equal(c.getImageData(150,147,1,1).data[3],0,m.id+' dark halo below ship');c=saved;c.drawImage(side,420,i*150);
 // The production 3D projection writes in screen coordinates; offset its canvas.
 const model=createCanvas(1050,180);c=model.getContext('2d');cyw=Math.cos(.55);syw=Math.sin(.55);cpt=Math.cos(.23);spt=Math.sin(.23);drawSub3D(0);c=saved;c.drawImage(model,0,i*150);
}
assert.equal(hashes.size,SUBS.length,'Each ship needs unique geometry');
`,world);
const dest=process.argv[2]||'/tmp/ship-lineup.png';fs.writeFileSync(dest,out.toBuffer('image/png'));
console.log('PASS: all nine menu/2D/3D renders, unique finite meshes. Preview: '+dest);
