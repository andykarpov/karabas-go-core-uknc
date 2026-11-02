"""Retiming for GO's discrete SDRAM: one IOB input bank, qualified read pipeline."""
import re

def remove_if(s,condition):
    start=s.index(condition)
    first=s.index('begin',start)
    depth=0
    for m in re.finditer(r'\bbegin\b|\bend\b',s[first:]):
        depth += 1 if m[0]=='begin' else -1
        if depth==0:
            end=first+m.end()
            # The q15 operation has an else branch.
            if s[end:].lstrip().startswith('else'):
                nxt=end+len(s[end:])-len(s[end:].lstrip())
                tail=s[nxt+4:]
                first2=tail.index('begin');depth=0
                for n in re.finditer(r'\bbegin\b|\bend\b',tail[first2:]):
                    depth+=1 if n[0]=='begin' else -1
                    if depth==0:return s[:start]+tail[first2+n.end():]
            return s[:start]+s[end:]
    raise ValueError(condition)

def retime(s):
    # Separate data capture from the controller's command/ack decisions.
    s=s.replace('always @(posedge clkram)begin\n   ppu_ll', '''(* IOB = "TRUE" *) reg [15:0] read_data;
reg [3:0] read_phase=0;
reg read_active=0;
always @(posedge clkram) begin
 read_data <= SDRAM_DQr;
 read_phase <= q;
 read_active <= lockclk && reset==0 && !refresh;
end

always @(posedge clkram)begin
   ppu_ll''',1)
    for q in (4,5,6,7,12,15):
        match=re.search(r"4'd"+str(q)+r'\s*: begin',s)
        end=s.index('endcase',match.end()) if q==15 else re.search(r"4'd"+str(q+1)+r'\s*: begin',s[match.end():]).start()+match.end()
        seg=s[match.start():end]
        if q in (4,5,6,7):
            seg=remove_if(seg,'if(get_regs_new)')
            seg=re.sub(r'pr_(?:blue|green|red)_data\s*<=\s*SDRAM_DQr[^;]*;','',seg)
        else:seg=remove_if(seg,'if(ppu_read_new)' if q==12 else 'if(cpu_select)')
        s=s[:match.start()]+seg+s[end:]
    ops='''
   // Read data and its phase advance together. Acknowledgements follow data.
   if(read_active)case(read_phase)
    4: if(get_regs)begin
        if(get_regs_new)begin
         if(qutro_reg)begin
          if(types_reg)vga_regc[15:0]<=read_data;else vga_regi[15:0]<=read_data;
         end else vga_adst<=read_data;
        end
       end else pr_blue_data<=read_data;
    5: if(get_regs && get_regs_new)begin
        if(qutro_reg)begin
         if(types_reg)vga_regc[31:16]<=read_data;else vga_regi[31:16]<=read_data;
        end else vga_adnx<=read_data;
       end
    6: if(get_regs && get_regs_new)begin
        if(qutro_reg)vga_adst<=read_data;else types_reg<=vga_adnx[2];
       end
    7: if(get_regs)begin
        if(get_regs_new)begin
         if(qutro_reg)begin
          vga_adnx<=read_data;curs_set<=read_data[0];qutro_reg<=read_data[1];types_reg<=read_data[2];
         end else begin qutro_reg<=vga_adnx[1];curs_set<=vga_adnx[0];end
        end
       end else begin pr_green_data<=read_data[7:0];pr_red_data<=read_data[15:8];end
    12: if(ppu_read_new)begin ppu_dout[15:0]<=read_data;ppu_ll<=cpu_select;end
    15: if(cpu_select)begin cpu_vl<=cpu_read_new;cpu_dout[31:16]<=read_data;end
        else begin ppu_hl<=ppu_read_new;ppu_dout[31:16]<=read_data;end
   endcase
'''
    s=s.replace("   cpu_vl <= 1'b0;", "   cpu_vl <= 1'b0;"+ops,1)
    # At phase 8 the serializer wants the phase-7 word on this same edge.
    s=s.replace('green_data <= pr_green_data;', "green_data <= (read_active && read_phase==7 && !get_regs) ? read_data[7:0] : pr_green_data;")
    s=s.replace('red_data   <= pr_red_data;', "red_data <= (read_active && read_phase==7 && !get_regs) ? read_data[15:8] : pr_red_data;")
    return s
