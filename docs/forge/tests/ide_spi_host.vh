reg sck=0,ss=1,mosi=0,bcs=1;wire miso;
wire [7:0] mounted,rxdata,result;wire [63:0] image_size;
wire data_wr,result_wr,qwr,qack;wire [8:0] rxaddr;wire [15:0] checksum;wire [23:0] qdata;
kg_mcu #(.ENABLE_RTC(0),.ENABLE_UART(0),.ENABLE_IMG(1),.ENABLE_FILE(0),.ENABLE_FT(0),.ENABLE_SD2(0),.BURST_MAX_MHZ(16)) host(
 .CLK(clk),.N_RESET(~rst),.MCU_MOSI(mosi),.MCU_MISO(miso),.MCU_SCK(sck),.MCU_SS(ss),
 .MCU_SPI_FT_SS(1'b1),.MCU_SPI_SD2_SS(1'b1),.MCU_BURST_CS_N(bcs),
 .IMG_MOUNTED(mounted),.IMG_SIZE(image_size),.IMG_DATA_WR(data_wr),.IMG_DATA_ADDR(rxaddr),.IMG_DATA(rxdata),
 .IMG_RESULT_WR(result_wr),.IMG_RESULT(result),.IMG_SUM(checksum),.IMG_Q_WR(qwr),.IMG_Q_DI(qdata),.IMG_Q_ACK(qack));
img_sdc #(.OUT_LATENCY(3)) bridge(.clk(clk),.reset(rst),.img_mounted(mounted),.img_size(image_size),
 .img_data_wr(data_wr),.img_data_addr(rxaddr),.img_data(rxdata),.img_result_wr(result_wr),.img_result(result),.img_sum(checksum),
 .img_q_wr(qwr),.img_q_di(qdata),.img_q_ack(qack),.sdc_rd({3'd0,rstart,4'd0}),.sdc_wr({3'd0,wstart,4'd0}),
 .sdc_sector(rsector),.sdc_busy(rbusy),.sdc_done(rdone),.sdc_byte_in_strobe(outen),.sdc_byte_addr(outaddr),.sdc_byte_in_data(inbyte),.sdc_byte_out_data(outbyte));
reg [23:0] reply;
reg [31:0] request_lba=0;reg [7:0] op=0;reg pending=0;
reg [7:0] bank=0;reg [15:0] wr_sum=0;reg [1:0] sum_seen=0;reg [511:0] seen=0;
task spi_frame(input [23:0] word);
 integer b;
 begin
  ss=0;reply=0;#200;
  for(b=23;b>=0;b=b-1)begin mosi=word[b];#32;reply={reply[22:0],miso};sck=1;#32;sck=0;end
  #200;ss=1;#400;
  case(reply[23:16])
   8'h42:if(reply[15:8]<4)request_lba[reply[15:8]*8+:8]=reply[7:0];
   8'h43:begin
    if(reply[15:8]!=4)$fatal(1,"Wrong IDE slot");
    pending=1;op=reply[7:0];sum_seen=0;seen=0;
   end
   8'h44:case(reply[15:8])
    0:bank=reply[7:0];
    8'h10:begin wr_sum[7:0]=reply[7:0];sum_seen[0]=1;end
    8'h11:begin wr_sum[15:8]=reply[7:0];sum_seen[1]=1;end
   endcase
   8'h45:begin wbuf[{bank[0],reply[15:8]}]=reply[7:0];seen[{bank[0],reply[15:8]}]=1;end
  endcase
 end
endtask
task burst_byte(input [7:0] value);
 integer b;
 begin for(b=7;b>=0;b=b-1)begin mosi=value[b];#32;sck=1;#32;sck=0;end end
endtask
integer byte_no,polls;reg [15:0] sum;
initial begin
 wait(!rst);spi_frame(24'hfd0000);spi_frame(24'hfe0000);
 forever begin
  spi_frame(0);
  if(pending)begin
   pending=0;sum=0;last_sector=request_lba;
   if(op==1)begin
    req_log[nreq]=request_lba;nreq=nreq+1;
    bcs=0;#200;burst_byte(8'h45);repeat(4)burst_byte(0);
    for(byte_no=0;byte_no<512;byte_no=byte_no+1)begin burst_byte(pat(request_lba,byte_no));sum=sum+pat(request_lba,byte_no);end
    #400;bcs=1;#400;
    spi_frame({8'h42,8'd0,sum[7:0]});spi_frame({8'h42,8'd1,sum[15:8]});spi_frame(24'h430001);
   end else if(op==2)begin
    polls=0;
    while(sum_seen!=3 && polls<2000)begin spi_frame(0);polls=polls+1;end
    if(sum_seen!=3 || !(&seen))$fatal(1,"Incomplete IDE write");
    for(byte_no=0;byte_no<512;byte_no=byte_no+1)sum=sum+wbuf[byte_no];
    if(sum!=wr_sum)$fatal(1,"IDE write checksum mismatch");
    nwr=nwr+1;spi_frame(24'h430001);
   end else $fatal(1,"Invalid IDE operation");
  end
  #1000;
 end
end
