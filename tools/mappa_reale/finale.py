import json, numpy as np, cv2, glob, os
R='/home/claude/diplomacy'
d=json.load(open(R+'/data/mappa.json')); P=d['province']
sig=[p['sigla'] for p in P]; tipo=[p['tipo'] for p in P]
st=json.load(open('stelle.json'))
seg=np.load('seg.npy').astype(np.int32); terra=np.load('terra.npy'); H,W=seg.shape
# pezzetti fuori gioco piccoli -> alla provincia vicina dello stesso tipo
fuori=(seg>=200).astype(np.uint8)
n,cc,stt,_=cv2.connectedComponentsWithStats(fuori)
via=np.zeros((H,W),bool)
for k in range(1,n):
    if stt[k,4]<500: via|=cc==k
# pezzetti staccati di una provincia (sotto 60 punti) -> al vicino
for v in range(1,76):
    n,cc,stt,_=cv2.connectedComponentsWithStats((seg==v).astype(np.uint8))
    if n>2:
        g=1+int(np.argmax(stt[1:,4]))
        for k in range(1,n):
            if k!=g and stt[k,4]<60: via|=cc==k
for msk in (terra,~terra):
    z=via&msk
    if z.any():
        _,ix=cv2.distanceTransformWithLabels((via|(~msk)).astype(np.uint8),cv2.DIST_L2,5,labelType=cv2.DIST_LABEL_PIXEL)
        src=np.zeros(ix.max()+1,np.int32); ok=(~via)&msk; src[ix[ok]]=seg[ok]; seg[z]=src[ix[z]]
seg[seg>=200]=0
seg[:68,:]=0; seg[1187:,:]=0; seg[:,:63]=0; seg[:,1821:]=0
# ---------- posizioni
def polo(mask, evita=None):
    n,cc,stt,_=cv2.connectedComponentsWithStats(mask.astype(np.uint8))
    g=1+int(np.argmax(stt[1:,4])); m=(cc==g).astype(np.uint8)
    dt=cv2.distanceTransform(m,cv2.DIST_L2,5)
    if evita is not None:
        yy,xx=np.mgrid[0:H,0:W]; ds=np.hypot(xx-evita[0],yy-evita[1]); dt=np.minimum(dt,0.75*ds)
    y,x=np.unravel_index(np.argmax(dt),dt.shape); return [int(x),int(y)],float(dt[y,x])
ped=[]; stella=[]; etic=[]
for i,p in enumerate(P):
    m=seg==i+1
    if m.sum()==0: raise SystemExit('provincia vuota '+sig[i])
    s=st.get(sig[i])
    q,r=polo(m,s)
    if r<7: print('stretta',sig[i],round(r,1))
    ped.append(q); stella.append(s if s else None); etic.append([q[0],q[1]+20])
coste=[]
def pv(j): return j if j<75 else d['coste'][j-75]['provincia']
for c in d['coste']:
    i=c['provincia']; m=(seg==i+1).astype(np.uint8)
    dt=cv2.distanceTransform(m,cv2.DIST_L2,5)
    mari=np.zeros((H,W),np.uint8)
    for j in c['adj_f']:
        if tipo[pv(j)]=='mare': mari|=(seg==pv(j)+1).astype(np.uint8)
    dm=cv2.distanceTransform(1-mari,cv2.DIST_L2,5)
    altri=np.zeros((H,W),np.uint8)       # i mari delle altre coste: starne lontani
    for c2 in d['coste']:
        if c2['provincia']==i and c2 is not c:
            for j in c2['adj_f']:
                if tipo[pv(j)]=='mare': altri|=(seg==pv(j)+1).astype(np.uint8)
    da=cv2.distanceTransform(1-altri,cv2.DIST_L2,5)
    ok=(dt>=7)&(da>22)
    if not ok.any(): ok=dt>=5
    sc=np.where(ok,dm,1e9); y,x=np.unravel_index(np.argmin(sc),sc.shape)
    x,y={'STP/NC':(1330,160),'STP/SC':(1232,432)}.get(c['sigla'],(x,y))
    coste.append([int(x),int(y)])
json.dump({'larghezza':W,'altezza':H,'pedina':ped+coste,'stella':stella,'etichetta':etic},open(R+'/data/mappa_reale.json','w'),separators=(',',':'))
# ---------- immagini
os.makedirs(R+'/assets/mappa_reale',exist_ok=True)
F=glob.glob('/home/claude/mod/x/Mods/Images/*10104401349837175366*.jpg')[0]
im=cv2.imread(F)
cv2.imwrite(R+'/assets/mappa_reale/base.jpg',im,[cv2.IMWRITE_JPEG_QUALITY,86])
S=cv2.resize(seg.astype(np.uint8),(W*2,H*2),interpolation=cv2.INTER_NEAREST)
T=cv2.resize(terra.astype(np.uint8),(W*2,H*2),interpolation=cv2.INTER_NEAREST)
riva=np.clip(cv2.distanceTransform(1-T,cv2.DIST_L2,5),0,40)
e=np.zeros(S.shape,np.uint8); e[:,1:][S[:,1:]!=S[:,:-1]]=1; e[1:,:][S[1:,:]!=S[:-1,:]]=1
bordo=1+np.clip(cv2.distanceTransform(1-e,cv2.DIST_L2,5),0,30)
T[:136,:]=1; T[2374:,:]=1; T[:,:126]=1; T[:,3642:]=1   # la cornice stampata non e' mare
idp=np.dstack([riva.astype(np.uint8),T*255,S,bordo.astype(np.uint8)])   # BGRA
cv2.imwrite(R+'/assets/mappa_reale/id.png',idp)
# quota: quella della mappa disegnata, portata sul tabellone
mx,my=np.load('tps_inv.npy'); fx,fy=np.load('flusso.npy')
yy,xx=np.mgrid[0:H,0:W].astype(np.float32)
jx=cv2.remap(mx,xx+fx,yy+fy,cv2.INTER_LINEAR); jy=cv2.remap(my,xx+fx,yy+fy,cv2.INTER_LINEAR)
q0=cv2.imread(R+'/assets/mappa/quota.png',0).astype(np.float32)/255
print('quota vecchia',q0.shape)
sx=q0.shape[1]/1835.0
q=cv2.remap(q0,jx*sx,jy*sx,cv2.INTER_LINEAR,borderValue=0)
dl=cv2.distanceTransform(terra.astype(np.uint8),cv2.DIST_L2,5)
rampa=np.clip(dl/7.0,0,1)**0.6
q=(0.07+np.maximum(q-0.07,0)*0.5)*rampa
q[seg==0]*=0.6
cornice=np.zeros((H,W),np.float32); cornice[:]=1; cornice[52:-52,52:-52]=0   # la cornice stampata resta piatta
q=q*(1-cornice)
q=cv2.GaussianBlur(q,(0,0),1.6)
cv2.imwrite(R+'/assets/mappa_reale/quota.png',np.clip(q*255,0,255).astype(np.uint8))
# controllo a vista
o=cv2.resize(im,(W,H))
for i,(x,y) in enumerate(ped+coste):
    cv2.circle(o,(x,y),9,(0,255,255) if i<75 else (255,128,0),2); cv2.putText(o,(sig+[c['sigla'] for c in d['coste']])[i],(x-12,y-11),cv2.FONT_HERSHEY_SIMPLEX,0.38,(255,255,255),1)
for s,(x,y) in st.items(): cv2.drawMarker(o,(x,y),(255,0,255),cv2.MARKER_CROSS,10,2)
cv2.imwrite('posizioni.png',o)
