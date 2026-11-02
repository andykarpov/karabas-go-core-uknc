#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include "rt11_volume.h"
static int rd(void *p,unsigned b,void *out){return fseek(p,b*512,SEEK_SET)||fread(out,1,512,p)!=512;}
static int wr(void *p,unsigned b,const void *in){return fseek(p,b*512,SEEK_SET)||fwrite(in,1,512,p)!=512;}
static int src(void *p,uint8_t *out){fread(out,1,512,p);return ferror(p);}
int main(int argc,char **argv){
 if(argc!=5)return 2;
 FILE *base=fopen(argv[1],"rb"),*sav=fopen(argv[2],"rb"),*out=fopen(argv[3],"w+b");
 if(!base||!sav||!out)return 3;
 uint8_t buf[4096];size_t n;while((n=fread(buf,1,sizeof(buf),base)))if(fwrite(buf,1,n,out)!=n)return 4;
 fseek(sav,0,SEEK_END);unsigned size=ftell(sav);rewind(sav);
 rt11_io_t io={rd,wr,out};char prog[8];const char *err="";
 int result=rt11_build(&io,argv[4],size,rt11sav_date(2026,10,28),src,sav,prog,&err);
 fclose(base);fclose(sav);fclose(out);
 if(result){fprintf(stderr,"%s\n",err);return 1;}
 puts(prog);return 0;
}
