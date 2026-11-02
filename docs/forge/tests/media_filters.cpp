#include "file_name.h"
#include <cstdio>
#include <cstdlib>
int main(int argc,char **argv) {
 if(argc<4)return 2;
 unsigned accepted=0;
 for(int i=3;i<argc;i++)if(kg_name_has_ext(argv[i],argv[1]))accepted++;
 unsigned expected=std::strtoul(argv[2],nullptr,10);
 if(accepted!=expected){std::fprintf(stderr,"Media filter accepted %u files; expected %u\n",accepted,expected);return 1;}
 std::printf("PASS: packaged filter %.4s accepts %u supplied files\n",argv[1],accepted);
}
