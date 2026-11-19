import json, numpy as np, cv2, sys
from skimage.segmentation import watershed
im=cv2.imread('lavoro.png'); H,W=im.shape[:2]
d=json.load(open('/home/claude/diplomacy/data/mappa.json'))
sig=[p['sigla'] for p in d['province']]; tipo=[p['tipo'] for p in d['province']]
st=json.load(open('stelle.json'))
w2=cv2.imread('id_warp2.png'); idw=w2[...,2].astype(np.int32); terra_w=w2[...,1]>127
g=cv2.GaussianBlur(cv2.cvtColor(im,cv2.COLOR_BGR2GRAY),(0,0),0.8)
bh=cv2.morphologyEx(g,cv2.MORPH_BLACKHAT,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(9,9))).astype(np.float32)
lab=cv2.cvtColor(cv2.GaussianBlur(im,(0,0),1.5),cv2.COLOR_BGR2LAB).astype(np.float32)
gr=sum(cv2.Sobel(lab[...,c],cv2.CV_32F,1,0)**2+cv2.Sobel(lab[...,c],cv2.CV_32F,0,1)**2 for c in range(3))**0.5
barr=cv2.GaussianBlur(bh,(0,0),1.0)*3.0+gr*0.25
barr[622:634,:]=np.minimum(barr[622:634,:],np.minimum(barr[620,:],barr[636,:])[None,:])
for s,(x,y) in st.items(): cv2.circle(barr,(x,y),10,0,-1)
# 1) terra / mare
EC=7
m2=np.zeros((H,W),np.int32)
dl=cv2.distanceTransform(terra_w.astype(np.uint8),cv2.DIST_L2,5); ds=cv2.distanceTransform((~terra_w).astype(np.uint8),cv2.DIST_L2,5)
m2[dl>EC]=1; m2[ds>EC]=2
# isolette e lingue sottili: il nucleo e' la parte piu' interna
n,cc=cv2.connectedComponents(terra_w.astype(np.uint8))
for k in range(1,n):
    mk=cc==k; mx=dl[mk].max()
    if mx<=EC: m2[mk&(dl>=0.6*mx)]=1
ts=watershed(barr,m2); terra=ts==1
n,cc,stt,_=cv2.connectedComponentsWithStats((~terra).astype(np.uint8))
for k in range(1,n):
    if stt[k,4]<400: terra[cc==k]=True
# 2) province, separatamente in terra e in mare
ER=float(sys.argv[1]) if len(sys.argv)>1 else 9
mark=np.zeros((H,W),np.int32)
for v in range(0,76):
    m=(idw==v)
    if v==0:
        n,cc=cv2.connectedComponents(m.astype(np.uint8))
        for k in range(1,n):
            mk=(cc==k).astype(np.uint8); dt=cv2.distanceTransform(mk,cv2.DIST_L2,5)
            mark[dt>min(ER,0.5*dt.max())]=200+(1 if terra_w[cc==k].mean()>0.5 else 0)
        continue
    dt=cv2.distanceTransform(m.astype(np.uint8),cv2.DIST_L2,5)
    mark[dt>min(ER,0.55*dt.max())]=v
for s_,(x,y) in st.items(): cv2.circle(mark,(x,y),13,0,-1)
for s_,(x,y) in st.items(): cv2.circle(mark,(x,y),6,sig.index(s_)+1,-1)
C=json.load(open('correzioni.json'))
for k,v in C.items():
    lab_=sig.index(k)+1 if k in sig else {'_terra':201,'_mare':200,'via':0}[k]
    for it in v:
        if len(it)==3: cv2.circle(mark,(it[0],it[1]),it[2],lab_,-1)
        else: cv2.line(mark,(it[0],it[1]),(it[2],it[3]),lab_,it[4])
mark[:40,:]=200; mark[-40:,:]=200; mark[:,:40]=200; mark[:,-40:]=200
e_terra=np.array([False]+[t!='mare' for t in tipo]+[False]*200)[:256]; e_terra[201]=True
mt=np.where(e_terra[mark]&terra,mark,0); ms=np.where((~e_terra[mark])&(~terra),mark,0)
seg=np.zeros((H,W),np.int32)
a=watershed(barr,mt,mask=terra); b=watershed(barr,ms,mask=~terra)
seg[terra]=a[terra]; seg[~terra]=b[~terra]
print('non assegnati',int((seg==0).sum()))
if (seg==0).any():
    # resti isolati: alla regione piu' vicina dello stesso tipo
    for msk in (terra,~terra):
        z=(seg==0)&msk
        if z.any():
            _,ix=cv2.distanceTransformWithLabels(((seg==0)|(~msk)).astype(np.uint8),cv2.DIST_L2,5,labelType=cv2.DIST_LABEL_PIXEL)
            src=np.zeros(ix.max()+1,np.int32); ok=(seg>0)&msk; src[ix[ok]]=seg[ok]; seg[z]=src[ix[z]]
np.save('seg.npy',seg.astype(np.int16)); np.save('terra.npy',terra)
np.save('seg_pieno.npy',cv2.resize(seg.astype(np.uint8),(W*2,H*2),interpolation=cv2.INTER_NEAREST))
for s,(x,y) in st.items():
    if seg[y,x]!=sig.index(s)+1: print('stella fuori',s,seg[y,x])
for k,v in C.items():
    if k in sig:
        for it in v:
            if len(it)==3 and seg[it[1],it[0]]!=sig.index(k)+1: print('etichetta fuori',k)
adj=set()
for a_,b_ in ((seg[:,1:],seg[:,:-1]),(seg[1:,:],seg[:-1,:])):
    m=a_!=b_
    pr,cn=np.unique(np.stack([a_[m],b_[m]],1),axis=0,return_counts=True)
    for (x,y),c in zip(pr.tolist(),cn.tolist()):
        if x<=75 and y<=75 and c>=3: adj.add((min(x,y)-1,max(x,y)-1))
vere=set()
def pv(j): return j if j<75 else d['coste'][j-75]['provincia']
for i,p in enumerate(d['province']):
    for j in p['adj_a']+p['adj_f']: vere.add((min(i,pv(j)),max(i,pv(j))))
for c in d['coste']:
    for j in c['adj_f']:
        i=c['provincia']
        if i!=pv(j): vere.add((min(i,pv(j)),max(i,pv(j))))
print('mancano:',sorted(sig[a]+'-'+sig[b] for a,b in vere-adj))
print('di troppo:',sorted(sig[a]+'-'+sig[b] for a,b in adj-vere))
for v in range(1,76):
    n,cc,stt,_=cv2.connectedComponentsWithStats((seg==v).astype(np.uint8))
    if n>2:
        ar=sorted(stt[1:,4].tolist(),reverse=True)
        if len(ar)>1 and ar[1]>60: print('a pezzi',sig[v-1],ar[:4])
