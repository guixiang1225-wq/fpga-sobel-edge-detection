from pathlib import Path
import json
v=Path(__file__).resolve().parent
W,H=800,480
rgb=[];gray=[]
for f in range(4):
 for y in range(H):
  for x in range(W):
   if f==0:p=0x7bef
   elif f==1:p=0xffff if (x//80)%2 else 0
   elif f==2:p=0xffff if (y//48)%2 else 0
   else:p=((x*109+y*251+x*y*13)^(x<<7)^(y<<3))&65535
   rgb.append(p);rr=p>>11;gg=(p>>5)&63;bb=p&31
   gray.append((77*(rr*8+rr//4)+150*(gg*4+gg//16)+29*(bb*8+bb//4)+128)//256)
binary=[0]*len(rgb);mag=[0]*len(rgb);stats=[]
for f in range(4):
 edges=eq=nx=ny=0
 for y in range(1,H-1):
  for x in range(1,W-1):
   i=f*W*H+y*W+x
   gx=gray[i-W+1]+2*gray[i+1]+gray[i+W+1]-gray[i-W-1]-2*gray[i-1]-gray[i+W-1]
   gy=gray[i+W-1]+2*gray[i+W]+gray[i+W+1]-gray[i-W-1]-2*gray[i-W]-gray[i-W+1]
   m=abs(gx)+abs(gy);binary[i]=65535 if m>=128 else 0
   z=min(m//4,255);mag[i]=((z>>3)<<11)|((z>>2)<<5)|(z>>3)
   edges+=m>=128;eq+=m==128;nx+=gx<0;ny+=gy<0
 stats.append(dict(frame=f,white_edges=edges,threshold_equal=eq,negative_gx=nx,negative_gy=ny))
for name,a,width in [('input_rgb.hex',rgb,4),('input_gray.hex',gray,2),('gold_binary.hex',binary,4),('gold_magnitude.hex',mag,4)]:
 (v/name).write_text(''.join(format(z,'0%dx'%width)+'\n' for z in a),encoding='ascii')
(v/'golden_stats.json').write_text(json.dumps(stats,indent=2),encoding='ascii')
