"""Bound ATA requests before they enter Karabas's retrying sector transport."""
def adapt(s):
    s=s.replace('    input             hdd_present,', '    input      [31:0] image_sectors, // actual mounted file capacity\n    input             hdd_present,')
    marker='// next sector, Hard.cpp NextSector(): CHS, or the LBA counted up'
    s=s.replace(marker,'''// Invalid CHS probes (including WDINIT's sector zero) are ATA errors,
// not retryable media transfers. Likewise never send an LBA past EOF.
task bad_location;
begin
 status <= ST_READY | ST_SEEK | ST_ERROR;
 error <= ER_BADLOC;
 rd_pending <= 0; pf_valid <= 0; restart <= 0; wr_pending <= 0;
 sd_rstart <= 0; sd_wstart <= 0; sectorcount <= 0; st <= S_IDLE;
end
endtask

'''+marker)
    s=s.replace('''S_RD_LBA1, S_WR_LBA1: begin
            if (lba_mode)''','''S_RD_LBA1, S_WR_LBA1: begin
            if (!lba_mode && (cursector == 0 || cursector > spt_r ||
                             {4'd0,curhead} >= heads_r || spt_r == 0)) begin
                bad_location;
            end else if (lba_mode)''')
    s=s.replace('''S_RD_REQ: begin
            // one requester''','''S_RD_REQ: begin
            if (sd_sector >= image_sectors) begin bad_location; end
            else begin
            // one requester''')
    s=s.replace('''S_RD_WAIT: if (sd_rdone)''','''end
        S_RD_WAIT: if (sd_rdone)''')
    s=s.replace('''S_WR_REQ: begin
            if (wprot)''','''S_WR_REQ: begin
            if (sd_sector >= image_sectors) begin bad_location; end
            else if (wprot)''')
    if s.count('bad_location;')!=4:raise RuntimeError('IDE bounds adaptation did not match')
    return s
