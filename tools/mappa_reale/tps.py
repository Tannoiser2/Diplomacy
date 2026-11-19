import json, numpy as np, cv2
from scipy.interpolate import RBFInterpolator
st=json.load(open('stelle.json'))
d=json.load(open('/home/claude/diplomacy/data/mappa.json'))
P={p['sigla']:p for p in d['province']}
A=np.array([P[s]['stella'] for s in st],float); B=np.array([st[s] for s in st],float)
C=np.load('C.npy')
def feat(a): x,y=a[:,0]/1000,a[:,1]/1000; return np.stack([np.ones_like(x),x,y,x*x,x*y,y*y],1)
ang=np.array([[0,0],[1835,0],[0,1360],[1835,1360],[900,0],[900,1360],[0,700],[1835,700]],float)
A2=np.vstack([A,ang]); B2=np.vstack([B,feat(ang)@C])
inv=RBFInterpolator(B2,A2,kernel='thin_plate_spline',smoothing=30.0)
W,H=1884,1242
yy,xx=np.mgrid[0:H:4,0:W:4]
q=inv(np.stack([xx.ravel(),yy.ravel()],1).astype(float)).reshape(yy.shape+(2,))
mx=cv2.resize(q[...,0].astype(np.float32),(W,H)); my=cv2.resize(q[...,1].astype(np.float32),(W,H))
np.save('tps_inv.npy',np.stack([mx,my]))
idj=cv2.imread('/home/claude/diplomacy/assets/mappa/id.png')
cv2.imwrite('id_warp.png',cv2.remap(idj,mx*2,my*2,cv2.INTER_NEAREST,borderValue=(0,0,0)))
