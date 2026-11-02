#pragma once
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#define MC0511_MEDIA "/mc0511-media"
struct Mc0511Geometry { uint8_t spt,heads,inverted;uint16_t cylinders; };
inline bool mc0511_path_allowed(const char *dir,const char *name=nullptr) {
 const size_t n=strlen(MC0511_MEDIA);
 if(strncmp(dir,MC0511_MEDIA,n) || (dir[n] && dir[n]!='/')) return false;
 for(const char *p=dir;*p;p++) {
  if(*p=='\\' || (*p=='/' && p[1]=='/')) return false;
  if(*p=='/' && p[1]=='.' && (!p[2] || p[2]=='/' || (p[2]=='.' && (!p[3] || p[3]=='/')))) return false;
 }
 return !name || (*name && strcmp(name,".") && strcmp(name,"..") && !strchr(name,'/') && !strchr(name,'\\'));
}
inline Mc0511Geometry mc0511_parse_geometry(const uint8_t *sector,uint64_t size) {
 Mc0511Geometry g={0,0,0,0};uint8_t b[512];memcpy(b,sector,512);
 unsigned w0=b[0]|b[1]<<8,w1=b[2]|b[3]<<8,w2=b[4]|b[5]<<8;
 if((w0==0x54a9 && w1==0xffef && w2==0xfeff)||(w0==0xab56 && w1==0x0010 && w2==0x0100)) {
  g.inverted=w0==0xab56;if(g.inverted)for(auto &v:b)v=~v;
  unsigned w4=b[8]|b[9]<<8,w5=b[10]|b[11]<<8;
  g.spt=w4;g.heads=g.spt?w5/g.spt:0;
 } else {
  uint8_t test=255;for(unsigned i=0x1f0;i<=0x1fb;i++)test&=b[i];
  g.inverted=test==255;g.spt=g.inverted?~b[0]:b[0];g.heads=g.inverted?~b[1]:b[1];
 }
 uint64_t cyl=0;if(g.spt && g.heads)cyl=size/512/g.spt/g.heads;
 g.cylinders=cyl>65535?65535:cyl;return g;
}
