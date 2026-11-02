"""Core-owned Mini board adapters. Reference pin interfaces remain read-only."""
import re

BOARDS = {'go': 'kg1', 'mini': 'kg2', 'minig': 'kg3'}

def top(text, board, reference):
    header = reference[:reference.index('\n);') + 3]
    body = text[text.index('   );') + 6:]
    body = body.replace('MCU_SPI_IO[1]', 'MCU_IO[0]').replace('MCU_SPI_IO[0]', 'MCU_IO[1]')
    body = re.sub(r' // GO reverses.*? // RP2040 IO0[^\n]*\n', '', body, flags=re.S)
    body = body.replace('.beeper(BEEPER)', '.beeper()')
    for name, value in [('INDEX', "1'b0"), ('TR00', "1'b0"), ('WPRT', "1'b1"), ('RDATA', "1'b0")]:
        body = body.replace(f'.FDC_{name}(FDC_{name})', f'.FDC_{name}({value})')
    body = re.sub(r'\.FDC_(\w+)\(FDC_\w+\)', r'.FDC_\1()', body)
    body = re.sub(r'^assign (?:\{VGA_R,VGA_G,VGA_B\}|VGA_HS|VGA_VS|DAC_MUTE|FT_OE_N)=.*\n', '', body, flags=re.M)
    body = re.sub(r'^ODDR2 video_clock.*\n', '', body, flags=re.M)
    if board == 'mini':
        body = re.sub(r'^ODDR2 dac_clock.*\n', '', body, flags=re.M)
        body = body.replace('.HP_WS(DAC_LRCK),.HP_DIN(DAC_DAT)', '.HP_WS(),.HP_DIN()')
        extra = """
kg_sigma_delta_dac #(.MSBI(15)) dac_l(.clk(clocks[0]), .reset(~locked),
 .din({~audio_l[15],audio_l[14:0]}), .dout(AUDIO_L));
kg_sigma_delta_dac #(.MSBI(15)) dac_r(.clk(clocks[0]), .reset(~locked),
 .din({~audio_r[15],audio_r[14:0]}), .dout(AUDIO_R));
assign FT_RESET=1'b0;
"""
    else:
        body = body.replace('DAC_LRCK', 'DAC_WS')
        body = re.sub(r'^assign (?:ESP_RESET_N|ESP_BOOT_N|MIDI_CLK|MIDI_RESET_N)=.*\n', '', body, flags=re.M)
        extra = "assign ESP32_SPI_CS_N=1'b1;\n"
    extra += """
// FT812 video is unused by this core. Leave its input bus undriven.
assign FT_CLK_OUT=1'b0;
assign ADC_CLK=1'b0;
assign ADC_BCK=1'bz;
assign ADC_LRCK=1'bz;
mc0511_hdmi hdmi(.clk(clocks[0]), .reset(~locked),
 .rgb(rgb), .hs(~hs), .vs(~vs), .de(de), .audio_l(audio_l), .audio_r(audio_r),
 .tmds_p(TMDS_P), .tmds_n(TMDS_N));
"""
    return header + body.replace('endmodule', extra + '\nendmodule\n`default_nettype wire')

def timing(text, board):
    text = text[:text.index('# Asynchronous floppy')]
    if board == 'mini':
        text = text[:text.index('# DIN/LRCK')]
    else:
        text = text.replace('DAC_LRCK', 'DAC_WS')
    return text

def machine(text):
    # Ignore stale saved physical-drive selections on boards without that connector.
    return re.sub(r'wire physical_selected=.*?;', "wire physical_selected=1'b0;", text, count=1, flags=re.S)
