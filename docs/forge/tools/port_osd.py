"""Keep font pixels aligned with the overlay's measured raster scale."""
from prepare import replace


def adapt(source):
    start = source.index(' overlay.vhd read the character')
    end = source.index('*/', start)
    source = source[:start] + ''' MC0511 adapter: retain the synchronous RAM read-ahead, but select font
 pixels directly with the scaled horizontal position. Commit bitmap and
 attribute at the cell boundary; popup cells use a full 16-step read-ahead.
''' + source[end:]
    source = replace(source,
        'wire paper = hcnt >= 8 && hcnt < PAPER_END_H + 8 && vcnt < PAPER_END_V;',
        '''wire [4:0] cell_width = osd_popup ? 5'd16 : 5'd8;
wire paper = hcnt >= cell_width && hcnt < PAPER_END_H + cell_width && vcnt < PAPER_END_V;''')
    start = source.index('reg load_dbl =')
    end = source.index('// ---------------- output', start)
    source = source[:start] + '''// Read the next cell ahead, then commit it on the last clock of this
// scaled cell. Index the bitmap with the same coordinate as the character
// address: no independent shifter rate (and no repeated load stretching).
wire last_pixel_clock = width < 500 ? 1'b1 :
                        width < 1000 ? hcnt_i[0] : &hcnt_i[1:0];
always @(posedge clk) begin
    if (paper2 && ph_attr)
        attr2 <= vram_do[7:0];
    if (paper2 && ph_font)
        bitmap2 <= font_word;
    if (paper2 && ph_load && last_pixel_clock) begin
        attr <= attr2;
        bitmap <= bitmap2;
    end
end

wire [2:0] pixel_column = osd_popup ? hcnt[3:1] : hcnt[2:0];
wire pixel = bitmap[3'd7 - pixel_column];

''' + source[end:]
    return source
