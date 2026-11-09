// Physical backend for the UKNC 177130/177132 interface. The retained VP128
// supplies bus ACK and drive/control registers; only physical reads are muxed.
// All logic is clocked at 25 MHz; no flux, STEP or bus strobes are clocks.
module uknc_physical_fdd #(
 parameter SPINUP_CYCLES=12500000
)(
 input wire clk, reset, selected, motor, step, dir, head, write_protect,
 input wire [16:0] bus_addr,
 input wire [15:0] bus_data,
 input wire bus_stb, bus_write, bus_ack,
 output reg [15:0] bus_out=0,
 input wire index_in, track0_in, protect_in, rdata_in,
 output wire [1:0] drive_out,
 output wire motor_out, dir_out, step_out, side_out, wgate_out, wdata_out
);
(* ASYNC_REG="TRUE" *) reg [1:0] index_s=0,track0_s=0,protect_s=3,rdata_s=0;
reg rdata_old=0;
always @(posedge clk)begin
 index_s<={index_s[0],index_in};track0_s<={track0_s[0],track0_in};
 protect_s<={protect_s[0],protect_in};rdata_s<={rdata_s[0],rdata_in};
 rdata_old<=rdata_s[1];
end
wire running=selected && motor && !reset;
wire protected_disk=write_protect || protect_s[1];
reg old_stb=0,old_step=0,old_head=0;
// Qualify by the legacy controller's ACK: its drive/head/motor registers have
// then changed together, including a command which selects the physical slot.
wire port_stb=bus_stb && bus_ack && bus_addr[15:2]==14'o37626;
wire access=port_stb && !old_stb && selected && !reset;
wire command=access && bus_write && !bus_addr[1];
wire data_write=access && bus_write && bus_addr[1];
wire data_read=access && !bus_write && bus_addr[1];
wire search=command && bus_data[8];
wire changing_head=old_head!=head;
reg mark=0,transfer_ready=0,write_mode=0;
reg [23:0] spinup=0;
reg [7:0] step_time=0;
always @(posedge clk)begin
 old_stb<=port_stb;old_step<=step;old_head<=head;
 if(!running)begin spinup<=0;step_time<=0;end
 else begin
  if(spinup<SPINUP_CYCLES)spinup<=spinup+1'b1;
  // 1 us direction setup followed by a 4 us active STEP pulse.
  if(step && !old_step)step_time<=125;
  else if(step_time!=0)step_time<=step_time-1'b1;
 end
end
wire rx_valid,rx_crc,tx_active,tx_pulse,tx_consumed,tx_crc;
wire [15:0] rx_data;
wire abort_access=!running || changing_head || (step && !old_step);
uknc_mfm_rx rx(.clk(clk),.reset(abort_access || write_mode),.search(search),
 .flux(rdata_s[1] && !rdata_old),.data(rx_data),.valid(rx_valid),.crc_ok(rx_crc));
uknc_mfm_tx tx(.clk(clk),.reset(abort_access || protected_disk || search || data_read),
 .write_word(data_write),.data(bus_data),.mark(mark),
 .restart_crc(command && bus_data[9] && !mark),
 .active(tx_active),.pulse(tx_pulse),.consumed(tx_consumed),.crc_out(tx_crc));
always @(posedge clk)begin
 if(abort_access)begin transfer_ready<=0;write_mode<=0;mark<=0;end
 else begin
  if(rx_valid || tx_consumed)transfer_ready<=1;
  if(data_write || data_read || search)transfer_ready<=0;
  if(data_write && !protected_disk)write_mode<=1;
  if(data_read || search)write_mode<=0;
 end
 // A command may change side and WM together. Keep the new WM even while
 // the old track's receiver/transmitter state is being discarded.
 if(command)mark<=bus_data[9];
 // Snapshot before clearing TR on a data-register read. ACK still comes from
 // the PPU-clocked controller, so the result settles before the PPU samples it.
 if(access && !bus_write)
  bus_out<=bus_addr[1]?rx_data:
   {index_s[1],write_mode?tx_crc:rx_crc,6'd0,transfer_ready,4'd0,
    protected_disk,(spinup==SPINUP_CYCLES) && running,track0_s[1]};
end
// GO B4 uses inverting open-drain buffers: zero means released on the cable.
// This single-drive mapping always uses connector drive-select 0.
assign drive_out=running?2'b01:2'b00;
assign motor_out=running;
assign dir_out=running && dir;
assign side_out=running && head;
assign step_out=running && step_time!=0 && step_time<=100;
assign wgate_out=running && !protected_disk && tx_active && !changing_head;
assign wdata_out=wgate_out && tx_pulse;
endmodule
