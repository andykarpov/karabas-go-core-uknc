// Firmware-side sector server exercising the physical Karabas SPI frame link.
// Test images are opened read-only. No hierarchy forces or storage bypasses.
reg [23:0] spi_reply;
reg [31:0] request_lba=0;
reg [7:0] request_slot=0,request_op=0;
reg request_pending=0;
integer active_slot=0;
integer media_fd=0,media_size=0,media_reads=0,media_errors=0;
integer media_fds[0:4],media_sizes[0:4];
integer init_slot;
initial for(init_slot=0;init_slot<5;init_slot=init_slot+1)begin media_fds[init_slot]=0;media_sizes[init_slot]=0;end
integer media_writes=0;
reg [7:0] sector_bytes[0:511];
reg [7:0] write_bytes[0:511];
reg [7:0] write_bank=0;
reg [15:0] write_sum=0;
reg [1:0] write_sum_seen=0;
reg [511:0] write_seen=0;
reg [4095:0] cow_sectors[integer];
string media_path;
task reply_frame(input [23:0] reply);
 begin
  if(reply[23:16]==8'h42 && reply[15:8]<4)
   request_lba[reply[15:8]*8+:8]=reply[7:0];
  if(reply[23:16]==8'h43)begin
   if(request_pending)$fatal(1,"Overlapping sector requests");
   request_slot=reply[15:8];request_op=reply[7:0];request_pending=1;
   write_sum_seen=0;write_seen=0;
  end
  if(reply[23:16]==8'h44)case(reply[15:8])
   0:write_bank=reply[7:0];
   8'h10:begin write_sum[7:0]=reply[7:0];write_sum_seen[0]=1;end
   8'h11:begin write_sum[15:8]=reply[7:0];write_sum_seen[1]=1;end
  endcase
  if(reply[23:16]==8'h45)begin
   write_bytes[{write_bank[0],reply[15:8]}]=reply[7:0];
   write_seen[{write_bank[0],reply[15:8]}]=1;
  end
 end
endtask
task mount_media(input integer slot);
 integer n,w0,w1,w2,spt,heads,cyl,inv;
 begin
  active_slot=slot;
  media_fd=$fopen(media_path,"rb");if(!media_fd)$fatal(1,"Cannot open media %s",media_path);
  n=$fseek(media_fd,0,2);media_size=$ftell(media_fd);n=$fseek(media_fd,0,0);
  media_fds[slot]=media_fd;media_sizes[slot]=media_size;
  if(slot==4)begin
   n=$fread(sector_bytes,media_fd);if(n!=512)$fatal(1,"Invalid HDD home block");
   w0={sector_bytes[1],sector_bytes[0]};w1={sector_bytes[3],sector_bytes[2]};w2={sector_bytes[5],sector_bytes[4]};
   if((w0==16'h54a9 && w1==16'hffef && w2==16'hfeff)||(w0==16'hab56 && w1==16'h0010 && w2==16'h0100))begin
    inv=w0==16'hab56;
    if(inv)for(n=0;n<512;n=n+1)sector_bytes[n]=~sector_bytes[n];
    spt={sector_bytes[9],sector_bytes[8]};heads={sector_bytes[11],sector_bytes[10]}/spt;
   end else begin
    inv=1;for(n=496;n<508;n=n+1)if(sector_bytes[n]!=255)inv=0;
    spt=inv?8'(~sector_bytes[0]):sector_bytes[0];heads=inv?8'(~sector_bytes[1]):sector_bytes[1];
   end
   cyl=media_size/512/spt/heads;
   frame({8'h05,8'd240,spt[7:0]});frame({8'h05,8'd241,heads[7:0]});frame({8'h05,8'd242,inv[7:0]});
   frame({8'h05,8'd243,cyl[7:0]});frame({8'h05,8'd244,cyl[15:8]});
   frame({8'h05,8'd29,8'd1});frame({8'h05,8'd30,7'd0,!$test$plusargs("COW")});frame({8'h05,8'd9,8'd3});
   $display("HDD geometry %d/%d/%d inverted=%d",cyl,heads,spt,inv);
  end
  frame({8'h40,8'd0,slot[7:0]});
  for(n=0;n<8;n=n+1)frame({8'h41,n[7:0],n<4?8'(media_size>>(n*8)):8'd0});
 end
endtask
task burst_byte(input [7:0] value);
 integer bitno;
 begin for(bitno=7;bitno>=0;bitno=bitno-1)begin mosi=value[bitno];#32;sck=1;#32;sck=0;end end
endtask
task poll_media;
 integer n,k;reg [15:0] sum;
 begin
  frame(0);
  if(request_pending)begin
   request_pending=0;sum=0;
   if(request_slot>4 || !media_fds[request_slot] || request_lba*512>=media_sizes[request_slot])$fatal(1,"Invalid request %d slot%d LBA%d",request_op,request_slot,request_lba);
   if(request_op==1)begin
   n=$fseek(media_fds[request_slot],request_lba*512,0);n=$fread(sector_bytes,media_fds[request_slot]);
   if(n!=512)$fatal(1,"Short image read");
   if(request_slot==4 && cow_sectors.exists(request_lba))for(k=0;k<512;k=k+1)sector_bytes[k]=cow_sectors[request_lba][k*8+:8];
   media_reads=media_reads+1;
   burst_cs=0;#200;
   burst_byte(8'h45);repeat(4)burst_byte(0);
   for(k=0;k<512;k=k+1)begin burst_byte(sector_bytes[k]);sum=sum+sector_bytes[k];end
   #400;burst_cs=1;#400;
   frame({8'h42,8'd0,sum[7:0]});frame({8'h42,8'd1,sum[15:8]});frame(24'h430001);
   end else if(request_op==2 && request_slot==4 && $test$plusargs("COW"))begin
    n=0;
    while(write_sum_seen!=3 && n<2000)begin frame(0);n=n+1;end
    if(write_sum_seen!=3 || !(&write_seen))$fatal(1,"Incomplete image write");
    for(k=0;k<512;k=k+1)sum=sum+write_bytes[k];
    if(sum!=write_sum)$fatal(1,"Image write checksum mismatch");
    for(k=0;k<512;k=k+1)cow_sectors[request_lba][k*8+:8]=write_bytes[k];
    media_writes=media_writes+1;frame(24'h430001);
   end else $fatal(1,"Unexpected write to read-only test image");
  end
 end
endtask
task media_wait(input integer duration_ms);
 time until_time;
 begin
  until_time=$time+duration_ms*64'd1000000;
  while($time<until_time)begin poll_media();#20000;end
 end
endtask
task media_key(input [7:0] key);
 begin
  frame({8'h01,8'h01,key});media_wait(40);frame(24'h010100);media_wait(40);
 end
endtask
