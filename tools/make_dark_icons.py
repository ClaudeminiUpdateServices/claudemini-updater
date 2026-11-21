# Builds the dark-mode app icons (Icon-<Name>-Dark@2x/@3x.png) from the light ones. Needs numpy and Pillow.
import numpy as np, sys
from PIL import Image, ImageFilter
import os
R=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','app','Resources')+'/'
S=180
def load(n): return np.asarray(Image.open(R+f'Icon-{n}@3x.png').convert('RGB')).astype(np.float32)
def smooth(x,a,b):
    t=np.clip((x-a)/(b-a),0,1); return t*t*(3-2*t)
def dark_base():
    y=np.linspace(0,1,S)[:,None,None]; x=np.linspace(0,1,S)[None,:,None]
    top=np.array([46,46,50],np.float32); bot=np.array([19,19,21],np.float32)
    base=top*(1-y)+bot*y
    # faint soft glow at the top, like the iOS dark tiles
    glow=np.exp(-(((x-.5)/.7)**2+((y-0.0)/.45)**2))*7
    return np.clip(base+glow,0,255)
def grad(c0,c1,c2=None):
    # diagonal gradient top-left -> bottom-right
    y=np.linspace(0,1,S)[:,None,None]; x=np.linspace(0,1,S)[None,:,None]
    t=(x+y)/2
    c0,c1=np.array(c0,np.float32),np.array(c1,np.float32)
    return c0*(1-t)+c1*t
def lift(c,k=0.12): return c+(255-c)*k
def comp(base,color,alpha):
    return base*(1-alpha[...,None])+color*alpha[...,None]
def white_alpha(a,lo=150,hi=225):
    return smooth(a.min(axis=2),lo,hi)
def save(n,img):
    im=Image.fromarray(np.clip(img,0,255).astype(np.uint8))
    im.save(R+f'Icon-{n}-Dark@3x.png',optimize=True)
    im.resize((120,120),Image.LANCZOS).save(R+f'Icon-{n}-Dark@2x.png',optimize=True)
    return im
def rrect(x0,y0,x1,y1,r,soft=1.2):
    yy,xx=np.mgrid[0:S,0:S].astype(np.float32)+0.5
    cx,cy=(x0+x1)/2,(y0+y1)/2; hx,hy=(x1-x0)/2-r,(y1-y0)/2-r
    dx=np.maximum(np.abs(xx-cx)-hx,0); dy=np.maximum(np.abs(yy-cy)-hy,0)
    d=np.sqrt(dx*dx+dy*dy)-r
    return np.clip(0.5-d/soft,0,1)
out={}
base=dark_base()
# SideStore: white sunburst on cyan->purple  => sunburst in cyan->purple on dark
a=load('SideStore'); out['SideStore']=save('SideStore',comp(base,lift(grad((0,205,255),(178,40,255)),.10),white_alpha(a,170,235)))
# Dopamine: white sunburst on deep teal->green
a=load('Dopamine'); out['Dopamine']=save('Dopamine',comp(base,lift(grad((20,150,190),(40,225,150)),.12),white_alpha(a,170,235)))
# Sileo: white cube on teal => cube teal, cut-outs and sunburst dark
a=load('Sileo'); out['Sileo']=save('Sileo',comp(base,lift(grad((60,240,220),(0,185,175)),.05),white_alpha(a,170,235)))
# Github: white disc on dark maroon => disc raspberry, cat dark, sunburst light
a=load('Github'); out['Github']=save('Github',comp(base,lift(grad((230,70,115),(150,25,75)),.04),white_alpha(a,170,235)))
# Chimera / Default: coloured glyph on a light background => same colours on dark
for n in ['Chimera','Default']:
    a=load(n)
    bg=np.median(a[:8,:8].reshape(-1,3),axis=0)
    diff=np.abs(a-bg).max(axis=2)
    al=smooth(diff,14,70)
    col=lift(a,0.22 if n=='Chimera' else 0.10)
    if n=='Default': col=np.clip((col-128)*1.12+128,0,255)
    out[n]=save(n,comp(base,col,al))
# LiveContainer
a=load('LiveContainer'); w=a.min(axis=2)
frame_all=smooth(w,40,100)*(1-smooth(w,170,215))     # light-blue frame
tile=smooth(w,170,215)                               # white tile
ringbox=rrect(41,41,139,139,19,1.5)                  # inner blue rounded square (ring + glyph)
blue=lift(grad((20,150,255),(30,90,255)),.08)
ringglyph=(1-smooth(w,60,150))*ringbox
img=base.copy()
img=comp(img,np.array([66,66,74],np.float32),frame_all*(1-ringbox)*0.85)
img=comp(img,blue,ringglyph)
# the white tile with its blueprint grid becomes the dark centre, grid lines stay faintly visible
grid=np.clip((tile-0.0),0,1)
img=comp(img,np.array([13,13,15],np.float32),tile*ringbox)
# faint grid: slightly lighter lines where the tile had grey lines
lines=smooth(235-a.min(axis=2),8,40)*tile*ringbox*(1-ringglyph)
img=comp(img,np.array([52,52,60],np.float32),lines*0.8)
out['LiveContainer']=save('LiveContainer',img)
names=['Default','SideStore','LiveContainer','Dopamine','Chimera','Sileo','Github']
sheet=Image.new('RGB',(S*7+80,S*2+30),(110,110,110))
for i,n in enumerate(names):
    sheet.paste(Image.open(R+f'Icon-{n}@3x.png'),(10+i*(S+10),10))
    sheet.paste(out[n],(10+i*(S+10),S+20))
if len(sys.argv)>1: sheet.save(sys.argv[1])
