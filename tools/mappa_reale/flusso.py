import numpy as np, cv2
im=cv2.imread('lavoro.png'); H,W=im.shape[:2]
g=cv2.GaussianBlur(cv2.cvtColor(im,cv2.COLOR_BGR2GRAY),(0,0),0.8)
bh=cv2.morphologyEx(g,cv2.MORPH_BLACKHAT,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(7,7))).astype(np.float32)
B=np.clip((bh-10)/25,0,1); B[:45,:]=0;B[-45:,:]=0;B[:,:45]=0;B[:,-45:]=0
idj=cv2.imread('/home/claude/diplomacy/assets/mappa/id.png')
def bordi(idc):
    e=np.zeros(idc.shape,np.float32); e[:,1:][idc[:,1:]!=idc[:,:-1]]=1; e[1:,:][idc[1:,:]!=idc[:-1,:]]=1; return e
idw=cv2.imread('id_warp.png')
yy,xx=np.mgrid[0:H,0:W].astype(np.float32)
fx=np.zeros((H,W),np.float32); fy=np.zeros((H,W),np.float32)
for it,(sb,win,sm) in enumerate([(6,61,22),(4,45,14),(3,41,12)]):
    cur=cv2.remap(idw,xx+fx,yy+fy,cv2.INTER_NEAREST)
    A=bordi(cur[...,2].astype(np.int32))
    a8=(np.clip(cv2.GaussianBlur(A,(0,0),sb)*sb*2.5,0,1)*255).astype(np.uint8)
    b8=(np.clip(cv2.GaussianBlur(B,(0,0),sb)*sb*1.2,0,1)*255).astype(np.uint8)
    fl=cv2.calcOpticalFlowFarneback(b8,a8,None,0.5,4,win,5,7,1.5,0)   # per ogni pixel della stampa: dove sta nella mappa nota
    dx=cv2.GaussianBlur(fl[...,0],(0,0),sm); dy=cv2.GaussianBlur(fl[...,1],(0,0),sm)
    nfx=cv2.remap(fx,xx+dx,yy+dy,cv2.INTER_LINEAR)+dx; nfy=cv2.remap(fy,xx+dx,yy+dy,cv2.INTER_LINEAR)+dy
    fx,fy=np.clip(nfx,-45,45),np.clip(nfy,-45,45)
    print(it, float(np.abs(dx).mean()), float(np.hypot(fx,fy).max()))
cur=cv2.remap(idw,xx+fx,yy+fy,cv2.INTER_NEAREST)
cv2.imwrite('id_warp2.png',cur); np.save('flusso.npy',np.stack([fx,fy]))
e=bordi(cur[...,2].astype(np.int32))>0
o=im.copy(); o[e]=(255,0,255)
big=cv2.resize(o,None,fx=2,fy=2,interpolation=cv2.INTER_CUBIC)
for i,(x0,y0) in enumerate([(380,330),(1000,60),(380,640),(760,560),(1000,640),(760,860),(1300,760),(380,880)]):
    cv2.imwrite('f%d.png'%i,big[y0*2:y0*2+1000,x0*2:x0*2+1500])
