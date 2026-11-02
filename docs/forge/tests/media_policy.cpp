#include <initializer_list>
#include "mc0511_media.h"
#include <cassert>
#include <cstdio>
int main(int argc,char **argv){
 assert(mc0511_path_allowed("/mc0511-media"));
 assert(mc0511_path_allowed("/mc0511-media/games","test.SAV"));
 const char *bad[]={"/","/mc0511-media-other","/mc0511-media/..","/mc0511-media/../secret","/mc0511-media/x/../../","/mc0511-media//x","/mc0511-media/./x","/mc0511-media\\x"};
 for(auto p:bad)assert(!mc0511_path_allowed(p));
 for(auto n:{"../bad.img","/bad.img","..",".","a/b.img","a\\b.img",""})assert(!mc0511_path_allowed("/mc0511-media",n));
 assert(argc==3);
 for(int i=1;i<argc;i++){
  FILE *f=fopen(argv[i],"rb");assert(f);uint8_t b[512];assert(fread(b,1,512,f)==512);fseek(f,0,SEEK_END);auto size=ftell(f);fclose(f);
  auto g=mc0511_parse_geometry(b,size);assert(g.spt && g.heads && g.cylinders);assert(g.inverted==(i==1));
  for(auto &v:b)v=~v;
  auto inverse=mc0511_parse_geometry(b,size);
  assert(g.spt==inverse.spt && g.heads==inverse.heads && g.cylinders==inverse.cylinders && g.inverted!=inverse.inverted);
  printf("PASS geometry %s: %u/%u/%u inverted=%u\n",argv[i],g.cylinders,g.heads,g.spt,g.inverted);
 }
 puts("PASS SD1 media path boundary, persisted traversal and both image encodings");
}
