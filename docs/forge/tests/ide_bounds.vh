    $display("[tb_ide] invalid CHS and EOF return ATA IDNF without media requests");
    image_sectors=1024; n0=nreq;
    regwr(2,1);regwr(3,0);regwr(4,0);regwr(5,0);regwr(6,8'ha0);regwr(7,8'h20);
    repeat(100)@(posedge clk);regrd(7,s);check("CHS sector zero: ERR, no BUSY/DRQ",s&8'h89,1);
    regrd(1,s);check("CHS sector zero: IDNF",s,8'h10);check("no invalid CHS fetch",nreq,n0);
    regwr(2,1);regwr(3,1);regwr(6,8'ha4);regwr(7,8'h20); // SETCFG above selected 4 heads
    repeat(100)@(posedge clk);regrd(7,s);check("head past geometry",s&8'h89,1);check("no invalid head fetch",nreq,n0);
    regwr(2,1);regwr(3,17);regwr(6,8'ha0);regwr(7,8'h20); // SETCFG above selected 16 sectors/track
    repeat(100)@(posedge clk);regrd(7,s);check("sector past track",s&8'h89,1);check("no invalid sector fetch",nreq,n0);
    regwr(2,1);regwr(3,0);regwr(4,4);regwr(5,0);regwr(6,8'he0);regwr(7,8'h20);
    repeat(100)@(posedge clk);regrd(7,s);check("LBA at EOF",s&8'h89,1);check("no EOF fetch",nreq,n0);
    n0=nwr;regwr(2,1);regwr(7,8'h30);
    for(i=0;i<256;i=i+1)datawr(16'ha55a);
    repeat(100)@(posedge clk);regrd(7,s);check("write at EOF",s&8'h89,1);check("no write beyond EOF",nwr,n0);
    regwr(2,1);regwr(3,8'hff);regwr(4,3);regwr(7,8'h20);wait_ready;
    check("last valid LBA after errors",last_sector,1023);
    for(i=0;i<256;i=i+1)datard(w);
