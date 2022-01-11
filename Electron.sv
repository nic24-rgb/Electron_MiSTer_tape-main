//============================================================================
//  Electron port to MiSTer
//  2019 Dave Wood (oldgit)
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [44:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output  [1:0] VGA_SL,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)
	//input         TAPE_IN,

	// SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,
	
	//ADC
	inout   [3:0] ADC_BUS,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..5 - USR1..USR4
	// Set USER_OUT to 1 to read from USER_IN.
	input   [5:0] USER_IN,
	output  [5:0] USER_OUT,

	input         OSD_STATUS
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;
 
assign LED_USER  = tape_adc_act;
//assign LED_DISK  = {1'b1,~vsd_sel & sd_act};
assign LED_POWER = 0;

assign VIDEO_ARX = status[1] ? 8'd16 : 8'd4;
assign VIDEO_ARY = status[1] ? 8'd9  : 8'd3; 

wire [1:0] scale = status[3:2];

`include "build_id.v" 
parameter CONF_STR = {
	"Electron;;",
	"-;",
//	"S,VHD;",
//	"OC,Autostart,Yes,No;",
	"-;",
	"O1,Aspect ratio,4:3,16:9;",
	"O23,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
//	"OA,Mouse as Joystick,Yes,No;",
//	"OB,Swap Joysticks,No,Yes;",
	"-;",
//	"O4,Model,B(MOS6502),Master(R65SC12);",
//	"O56,Co-Processor,None,MOS65C02;",
//	"O78,VIDEO,sRGB-interlaced,sRGB-non-interlaced,SVGA-50Hz,SVGA-60Hz;",
	"-;",
	"R0,Reset;",
	"JA,Fire;",
	"V,v",`BUILD_DATE
};

/////////////////  CLOCKS  ////////////////////////

wire clk_sys; //96mhz
wire clk_16;
wire clk_24;
wire clk_32;
wire clk_33p3;
wire clk_40;
wire clk_48;
wire clk_120;
wire clk_100;

xtra_pll xtra_pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_33p3),
	.outclk_1(clk_100)
);


pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_16),
	.outclk_1(clk_24),
	.outclk_2(clk_32),
	.outclk_3(clk_40),
	.outclk_4(clk_48),
	.outclk_5(clk_sys),
	.outclk_6(clk_120)
);

reg vid_clk;
reg [1:0] old_state;
always @(posedge clk_sys) begin
	if (old_state != status[8:7]) begin
		old_state <= status[8:7];
		case (status[8:7])
			'b00: vid_clk <= clk_48;
			'b01: vid_clk <= clk_48;
			'b10: vid_clk <= clk_100;
			'b11: vid_clk <= clk_120;
		endcase
	end
end


/////////////////  HPS  ///////////////////////////

wire [31:0] status;
wire  [1:0] buttons;

wire [15:0] joy1, joy2;
wire  [7:0] joy1_x,joy1_y,joy2_x,joy2_y;

wire [10:0] ps2_key;
wire [24:0] ps2_mouse;

wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        forced_scandoubler;

wire [31:0] sd_lba;
wire        sd_rd;
wire        sd_wr;
wire        sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din;
wire        sd_buff_wr;
wire        img_mounted;
wire        img_readonly;
wire [63:0] img_size;
wire        sd_ack_conf;

wire [64:0] RTC;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),
	.forced_scandoubler(forced_scandoubler),

	.RTC(RTC),

	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),

	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_ack_conf(sd_ack_conf),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),

	.joystick_0(joy1),
	.joystick_1(joy2),
	.joystick_analog_0({joy1_y,joy1_x}),
	.joystick_analog_1({joy2_y,joy2_x})
);

/////////////////  RESET  /////////////////////////

wire reset = RESET | status[0] | buttons[1] | (~status[12] & img_mounted);

////////////////  MEMORY  /////////////////////////

//reg m128 = 0;
//always @(posedge clk_sys) if(reset_req) m128 <= status[4];

// ELK ROM Images

// The first 8 are sideways rams

// 00 00xx empty     
// 00 01xx empty     
// 00 10xx empty     
// 00 11xx empty     
// 01 00xx mmfs_swram.rom         
// 01 01xx empty     
// 01 10xx empty     
// 01 11xx empty     
// 10 00xx os100.rom      
// 10 01xx os100.rom     
// 10 10xx Basic2.rom      
// 10 11xx Basic2.rom      
// 11 00xx pres_ap2_v1_23.rom     
// 11 01xx empty     
// 11 10xx empty
// 11 11xx M7_191.rom    

always_comb begin
	rom_addr[13:0] = mem_addr[13:0];
	case({mem_addr[18:14]})
		'b0_01_00: rom_addr[16:14] =  0; //mmfs_swram.rom        
		'b0_10_00: rom_addr[16:14] =  1; //os100.rom     
		'b0_10_01: rom_addr[16:14] =  1; //os100.rom 
		'b0_10_10: rom_addr[16:14] =  2; //Basic2.rom 
		'b0_10_11: rom_addr[16:14] =  2; //Basic2.rom 
		'b0_11_00: rom_addr[16:14] =  3; //pres_ap2_v1_23.rom      
		'b0_11_01: rom_addr[16:14] =  4; //empty  for future use   
		'b0_11_10: rom_addr[16:14] =  5; //empty  for future use     
		'b0_11_11: rom_addr[16:14] =  6; //M7_191.rom          
		  default: rom_addr[16:14] =  0;
	endcase
end

always_comb begin
	case({mem_addr[18:14]})
		'b0_01_00,
		'b0_10_00,
		'b0_10_01,
		'b0_10_10,
		'b0_10_11,
		'b0_11_00,
		'b0_11_01,
		'b0_11_10,
		'b0_11_11: rom_data = rom_dout;
		  default: rom_data = 0;
	endcase
end

wire        mem_we_n;
wire [18:0] mem_addr;
wire  [7:0] mem_din;
wire  [7:0] ram_dout;
reg  [7:0] ram_data;

reg  [17:0] ram_addr;
reg  [16:0] rom_addr;
wire  [7:0] rom_dout;
reg   [7:0] rom_data;

spram #(8, 17, 114688, "roms/ELK.mif") rom
(
	.clock(clk_sys),
	.address(reset ? ioctl_addr[16:0] : rom_addr),
	.data(ioctl_dout),
	.wren(!ioctl_index && ioctl_wr && reset),
	.q(rom_dout)
);

always_comb begin
	ram_addr[13:0] = mem_addr[13:0];
	case({mem_addr[18:14]})
		'b1_00_00: ram_addr[16:14] =  0; //swram        
		'b1_00_01: ram_addr[16:14] =  1; //swram     
		'b1_00_10: ram_addr[16:14] =  2; //swram 
		'b1_00_11: ram_addr[16:14] =  3; //swram 
		'b1_01_00: ram_addr[16:14] =  4; //mmfs_swram.ram 
		'b1_01_01: ram_addr[16:14] =  5; //swram     
		'b1_01_10: ram_addr[16:14] =  6; //swram   
		'b1_01_11: ram_addr[16:14] =  7; //swram           
		  default: ram_addr[16:14] =  0;
	endcase
end

always_comb begin
	case({mem_addr[18:14]})
		'b1_00_00,
		'b1_00_01,
		'b1_00_10,
		'b1_00_11,
		'b1_01_00,
		'b1_01_01,
		'b1_01_10,
		'b1_01_11: ram_data = ram_dout;
		  default: ram_data = 0;
	endcase
end

spram #(8, 17, 131072) ram
(
	.clock(clk_sys),
	.address(ram_addr),
	.data(mem_din),
	.wren(mem_addr[18] & old_we & ~mem_we_n),
	.q(ram_dout)
);

reg old_we;
always @(posedge clk_sys) old_we <= mem_we_n;

///////////////////////////////////////////////////

wire reset_req;

wire [7:0] joya_x = 8'hFF - {~ax[7],ax[6:0]};
wire [7:0] joya_y = 8'hFF - {~ay[7],ay[6:0]};
wire [7:0] joyb_x = 8'hFF - {~joy2_x[7],joy2_x[6:0]};
wire [7:0] joyb_y = 8'hFF - {~joy2_y[7],joy2_y[6:0]};

ElectronFpga_core Electron
(
	.clk_16M00(clk_16),
	.clk_24M00(clk_24),
	.clk_32M00(clk_32),
	.clk_33M33(clk_33p3),
	.clk_40M00(clk_40),

	.hard_reset_n(~reset),

	.ps2_key(ps2_key),
//	.ps2_mouse(status[10] ? ps2_mouse : 25'd0),

//	.video_sel(clk_sel),
	.video_cepix(ce_pix),
	.video_red(r),
	.video_green(g),
	.video_blue(b),
	.video_vblank(vblank),
	.video_hblank(hblank),
	.video_vsync(vs),
	.video_hsync(hs),

	.audio_l(audio_snl),
	.audio_r(audio_snr),

	.ext_nOE(),
	.ext_nWE(mem_we_n),
	.ext_A(mem_addr),
	.ext_Dout(mem_addr[18] ? ram_data : rom_data),
	.ext_Din(mem_din),

	.SDMISO(sdmiso),
	.SDCLK(sdclk),
	.SDMOSI(sdmosi),
	.SDSS(sdss),

	.caps_led(),
	.motor_led(),
	
	.cassette_in(tape_in),
	.cassette_out(),
	//     -- Format of Video
   //     -- 00 - sRGB - interlaced
   //     -- 01 - sRGB - non interlaced
   //     -- 10 - SVGA - 50Hz
   //     -- 11 - SVGA - 60Hz
	.vid_mode(2'b11)
//	.vid_mode(status[8:7])
	
//	.RTC(RTC),

/*
	.keyb_dip({4'd0, ~status[12], ~status[9:7]}),

	.joystick1_x(    status[11] ? {joyb_x,joyb_x[7:4]} : {joya_x,joya_x[7:4]}),
	.joystick1_y(    status[11] ? {joyb_y,joyb_y[7:4]} : {joya_y,joya_y[7:4]}),
	.joystick1_fire( status[11] ? ~joy2[4] : ~af),

	.joystick2_x(   ~status[11] ? {joya_x,joya_x[7:4]} : {joyb_x,joyb_x[7:4]}),
	.joystick2_y(   ~status[11] ? {joya_y,joya_y[7:4]} : {joyb_y,joyb_y[7:4]}),
	.joystick2_fire(~status[11] ? ~joy2[4] : ~af),

	.m128_mode(m128),
	.copro_mode(|status[6:5])*/
);

wire  audio_snl,audio_snr;

assign AUDIO_L = {16{audio_snl}};
assign AUDIO_R = {16{audio_snr}};
assign AUDIO_MIX = 0;
assign AUDIO_S = 0;

wire hs, vs, hblank, vblank, ce_pix, clk_sel;
wire [3:0] r,g,b;

assign CLK_VIDEO = clk_120;
video_mixer #(640, 1) mixer
(
	.clk_sys(CLK_VIDEO),
	
	.ce_pix(ce_pix),
	.ce_pix_out(CE_PIXEL),

	.hq2x(scale == 1),
	.scanlines(0),
	.scandoubler(scale),

	.R({r,r}),
	.G({g,g}),
	.B({b,b}),

	.mono(0),

	.HSync(~hs),
	.VSync(~vs),
	.HBlank(hblank),
	.VBlank(vblank),

	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_VS(VGA_VS),
	.VGA_HS(VGA_HS),
	.VGA_DE(VGA_DE)
);

assign VGA_F1 = 0;
assign VGA_SL = scale ? scale - 1'd1 : 2'd0;

/////////////////// TAPE  /////////////////////

wire tape_in;
wire tape_adc, tape_adc_act;

assign tape_in = tape_adc;

ltc2308_tape ltc2308_tape
(
	.clk(CLK_50M),
	.ADC_BUS(ADC_BUS),
	.dout(tape_adc),
	.active(tape_adc_act)
);


//////////////////   SD   ///////////////////

wire sdclk;
wire sdmosi;
wire sdmiso = vsd_sel ? vsdmiso : SD_MISO;
wire sdss;

reg vsd_sel = 0;
always @(posedge clk_sys) if(img_mounted) vsd_sel <= |img_size;

wire vsdmiso;
sd_card sd_card
(
	.*,

	.clk_spi(clk_sys),
	.sdhc(1),
	.sck(sdclk),
	.ss(sdss | ~vsd_sel),
	.mosi(sdmosi),
	.miso(vsdmiso)
);

assign SD_CS   = sdss   |  vsd_sel;
assign SD_SCK  = sdclk  & ~vsd_sel;
assign SD_MOSI = sdmosi & ~vsd_sel;

reg sd_act;

always @(posedge clk_sys) begin
	reg old_mosi, old_miso;
	integer timeout = 0;

	old_mosi <= sdmosi;
	old_miso <= sdmiso;

	sd_act <= 0;
	if(timeout < 2000000) begin
		timeout <= timeout + 1;
		sd_act <= 1;
	end

	if((old_mosi ^ sdmosi) || (old_miso ^ sdmiso)) timeout <= 0;
end


//////////////////   ANALOG AXIS   ///////////////////
reg        emu = 0;
wire [7:0] ax = emu ? mx[7:0] : joy1_x;
wire [7:0] ay = emu ? my[7:0] : joy1_y;
wire [7:0] af = emu ? |ps2_mouse[1:0] : joy1[4];

reg  signed [8:0] mx = 0;
wire signed [8:0] mdx = {ps2_mouse[4],ps2_mouse[4],ps2_mouse[15:9]};
wire signed [8:0] mdx2 = (mdx > 10) ? 9'd10 : (mdx < -10) ? -8'd10 : mdx;
wire signed [8:0] nmx = mx + mdx2;

reg  signed [8:0] my = 0;
wire signed [8:0] mdy = {ps2_mouse[5],ps2_mouse[5],ps2_mouse[23:17]};
wire signed [8:0] mdy2 = (mdy > 10) ? 9'd10 : (mdy < -10) ? -9'd10 : mdy;
wire signed [8:0] nmy = my - mdy2;

always @(posedge clk_sys) begin
	reg old_stb = 0;
	
	old_stb <= ps2_mouse[24];
	if(old_stb != ps2_mouse[24]) begin
		emu <= 1;
		mx <= (nmx < -128) ? -9'd128 : (nmx > 127) ? 9'd127 : nmx;
		my <= (nmy < -128) ? -9'd128 : (nmy > 127) ? 9'd127 : nmy;
	end

	if(joy1 || reset_req || status[10]) begin
		emu <= 0;
		mx <= 0;
		my <= 0;
	end
end

endmodule

//////////////////////////////////////////////

module spram #(parameter DATAWIDTH=8, ADDRWIDTH=8, NUMWORDS=1<<ADDRWIDTH, MEM_INIT_FILE="")
(
	input	                 clock,
	input	 [ADDRWIDTH-1:0] address,
	input	 [DATAWIDTH-1:0] data,
	input	                 wren,
	output [DATAWIDTH-1:0] q
);

altsyncram altsyncram_component
(
	.address_a (address),
	.clock0 (clock),
	.data_a (data),
	.wren_a (wren),
	.q_a (q),
	.aclr0 (1'b0),
	.aclr1 (1'b0),
	.address_b (1'b1),
	.addressstall_a (1'b0),
	.addressstall_b (1'b0),
	.byteena_a (1'b1),
	.byteena_b (1'b1),
	.clock1 (1'b1),
	.clocken0 (1'b1),
	.clocken1 (1'b1),
	.clocken2 (1'b1),
	.clocken3 (1'b1),
	.data_b (1'b1),
	.eccstatus (),
	.q_b (),
	.rden_a (1'b1),
	.rden_b (1'b1),
	.wren_b (1'b0)
);

defparam
	altsyncram_component.clock_enable_input_a = "BYPASS",
	altsyncram_component.clock_enable_output_a = "BYPASS",
	altsyncram_component.init_file = MEM_INIT_FILE,
	altsyncram_component.intended_device_family = "Cyclone V",
	altsyncram_component.lpm_type = "altsyncram",
	altsyncram_component.numwords_a = NUMWORDS,
	altsyncram_component.operation_mode = "SINGLE_PORT",
	altsyncram_component.outdata_aclr_a = "NONE",
	altsyncram_component.outdata_reg_a = "UNREGISTERED",
	altsyncram_component.power_up_uninitialized = "FALSE",
	altsyncram_component.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
	altsyncram_component.widthad_a = ADDRWIDTH,
	altsyncram_component.width_a = DATAWIDTH,
	altsyncram_component.width_byteena_a = 1;


endmodule
